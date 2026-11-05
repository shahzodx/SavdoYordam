package httpapi

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/getsentry/sentry-go"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"savdoyordam/api/internal/dbgen"
)

type Server struct {
	DB      *pgxpool.Pool
	log     *slog.Logger
	limiter *limiter
}
type apiError struct {
	Status int
	Code   string
}

func (e *apiError) Error() string        { return e.Code }
func fail(status int, code string) error { return &apiError{status, code} }

type contextKey int

const userKey contextKey = 1

func user(r *http.Request) string { return r.Context().Value(userKey).(string) }
func New(db *pgxpool.Pool, log *slog.Logger) http.Handler {
	s := &Server{DB: db, log: log, limiter: &limiter{entries: map[string]bucket{}}}
	r := chi.NewRouter()
	r.Use(middleware.RequestID, middleware.Recoverer)
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("X-Content-Type-Options", "nosniff")
			w.Header().Set("Cache-Control", "no-store")
			started := time.Now()
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			next.ServeHTTP(ww, r)
			log.Info("request", "method", r.Method, "status", ww.Status(), "duration_ms", time.Since(started).Milliseconds(), "request_id", middleware.GetReqID(r.Context()))
			if ww.Status() >= 500 && sentry.CurrentHub().Client() != nil {
				sentry.CaptureEvent(&sentry.Event{Message: "API request failed", Level: sentry.LevelError, Tags: map[string]string{"request_id": middleware.GetReqID(r.Context()), "method": r.Method, "route": chi.RouteContext(r.Context()).RoutePattern()}})
			}

		})
	})
	r.Get("/health/live", func(w http.ResponseWriter, r *http.Request) { write(w, 200, map[string]string{"status": "ok"}) })
	r.Get("/health/ready", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if db.Ping(ctx) != nil {
			write(w, 503, map[string]string{"status": "unavailable"})
			return
		}
		write(w, 200, map[string]string{"status": "ok"})
	})
	r.Route("/v1", func(r chi.Router) {
		r.With(s.authLimit).Post("/auth/register", s.handle(s.register))
		r.With(s.authLimit).Post("/auth/login", s.handle(s.login))
		r.Group(func(r chi.Router) {
			r.Use(s.authenticate)
			r.Post("/auth/logout", s.handle(s.logout))
			r.With(s.authLimit).Post("/auth/delete", s.handle(s.deleteAccount))
			r.With(s.authLimit).Post("/auth/password", s.handle(s.changePassword))
			r.Get("/auth/sessions", s.handle(s.sessions))
			r.Post("/auth/sessions/revoke", s.handle(s.revokeSession))
			r.Post("/invitations/accept", s.handle(s.acceptInvite))
			r.Get("/stores", s.handle(s.stores))
			r.Post("/stores", s.handle(s.createStore))
			r.Route("/stores/{store}", func(r chi.Router) {
				r.Use(s.member)
				r.Post("/notifications/register", s.handle(s.registerPush))
				r.Post("/notifications/unregister", s.handle(s.unregisterPush))
				r.Get("/settings", s.handle(s.storeSettings))
				r.Post("/settings", s.handle(s.editStoreSettings))
				r.Get("/export", s.handle(s.exportStore))
				r.Get("/audit", s.handle(s.audit))
				r.Get("/members", s.handle(s.members))
				r.Get("/invitations", s.handle(s.invitations))
				r.Post("/invitations", s.handle(s.invite))
				r.Post("/invitations/{invitation}/revoke", s.handle(s.revokeInvite))
				r.Post("/members/{member}/remove", s.handle(s.removeMember))
				r.Get("/purchases", s.handle(s.purchases))
				r.Post("/purchases", s.handle(s.createPurchase))
				r.Get("/purchases/{purchase}", s.handle(s.purchaseDetail))
				r.Get("/offline", s.handle(s.offlineStatus))
				r.Post("/offline/enable", s.handle(s.enableOffline))
				r.Post("/offline/disable", s.handle(s.disableOffline))
				r.Get("/products", s.handle(s.products))
				r.Post("/products", s.handle(s.createProduct))
				r.Post("/products/{product}", s.handle(s.editProduct))
				r.Post("/inventory", s.handle(s.adjustInventory))
				r.Get("/inventory/{product}", s.handle(s.inventory))
				r.Get("/customers", s.handle(s.customers))
				r.Post("/customers", s.handle(s.createCustomer))
				r.Post("/customers/{customer}/payments", s.handle(s.customerPayment))
				r.Get("/customers/{customer}/ledger", s.handle(s.customerLedger))
				r.Get("/sales", s.handle(s.sales))
				r.Post("/sales", s.handle(s.createSale))
				r.Get("/sales/{sale}", s.handle(s.saleDetail))
				r.Post("/sales/{sale}/payments", s.handle(s.repay))
				r.Post("/sales/{sale}/return", s.handle(s.returnSale))
				r.Get("/expenses", s.handle(s.expenses))
				r.Post("/expenses", s.handle(s.createExpense))
				r.Post("/expenses/{expense}/void", s.handle(s.voidExpense))
				r.Get("/dashboard", s.handle(s.report))
				r.Get("/reports", s.handle(s.report))
				r.Get("/analytics", s.handle(s.analytics))
			})
		})
	})
	return r
}
func write(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func (s *Server) handle(fn func(http.ResponseWriter, *http.Request) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := fn(w, r); err != nil {
			s.respondError(w, r, err)
		}
	}
}
func (s *Server) respondError(w http.ResponseWriter, r *http.Request, err error) {
	var ae *apiError
	var pe *pgconn.PgError
	if errors.As(err, &ae) {
		write(w, ae.Status, map[string]string{"error": ae.Code})
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		write(w, 404, map[string]string{"error": "not_found"})
		return
	}
	if errors.As(err, &pe) && (pe.Code == "23505" || pe.Code == "23503" || pe.Code == "23514" || pe.Code == "22P02") {
		write(w, 409, map[string]string{"error": "data_conflict"})
		return
	}
	s.log.Error("request failed", "request_id", middleware.GetReqID(r.Context()), "error_type", strings.SplitN(err.Error(), ":", 2)[0])
	write(w, 500, map[string]string{"error": "server_error"})
}
func decode(w http.ResponseWriter, r *http.Request, v any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 65536)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		return fail(400, "invalid_request")
	}
	if d.Decode(new(any)) != io.EOF {
		return fail(400, "invalid_request")
	}
	return nil
}
func validID(id string) bool { _, err := uuid.Parse(id); return err == nil }
func digest(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func (s *Server) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		id, err := dbgen.New(s.DB).SessionUser(r.Context(), digest([]byte(token)))
		if err != nil {
			if !errors.Is(err, pgx.ErrNoRows) {
				s.respondError(w, r, err)
			} else {
				write(w, 401, map[string]string{"error": "unauthorized"})
			}
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userKey, id)))
	})
}
func (s *Server) member(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "store")
		if !validID(id) {
			write(w, 404, map[string]string{"error": "not_found"})
			return
		}
		var ok bool
		err := s.DB.QueryRow(r.Context(), "SELECT EXISTS(SELECT 1 FROM store_members m JOIN stores s ON s.id=m.store_id WHERE m.store_id=$1 AND m.user_id=$2 AND NOT s.archived)", id, user(r)).Scan(&ok)
		if err != nil {
			s.respondError(w, r, err)
			return
		}
		if !ok {
			write(w, 404, map[string]string{"error": "not_found"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Every write to a store takes its row lock. This deliberately serializes the small
// shop workload, preventing overselling and overpayment without distributed locks.
func (s *Server) command(w http.ResponseWriter, r *http.Request, payload any, owner bool, fn func(pgx.Tx) (any, string, error)) error {
	store := chi.URLParam(r, "store")
	key := r.Header.Get("Idempotency-Key")
	if !validID(key) {
		return fail(400, "idempotency_key_required")
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	hash := digest(append([]byte(r.URL.Path+"\n"), raw...))
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	var lock string
	if err = tx.QueryRow(r.Context(), "SELECT id::text FROM stores WHERE id=$1 FOR UPDATE", store).Scan(&lock); err != nil {
		return err
	}
	var role string
	if err = tx.QueryRow(r.Context(), "SELECT role FROM store_members WHERE store_id=$1 AND user_id=$2", store, user(r)).Scan(&role); err != nil {
		return err
	}
	if owner && role != "owner" {
		return fail(403, "permission_denied")
	}
	var oldHash, actor string
	var response []byte
	err = tx.QueryRow(r.Context(), "SELECT request_hash,actor_id::text,response FROM sync_operations WHERE store_id=$1 AND command_id=$2", store, key).Scan(&oldHash, &actor, &response)
	if err == nil {
		if oldHash != hash || actor != user(r) {
			return fail(409, "idempotency_conflict")
		}
		w.Header().Set("Idempotency-Replayed", "true")
		write(w, 200, json.RawMessage(response))
		return nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if err = s.enforceLease(r, tx); err != nil {
		return err
	}
	var requestDetails map[string]any
	_ = json.Unmarshal(raw, &requestDetails)
	snapshotID := chi.URLParam(r, "product")
	if snapshotID == "" && strings.HasSuffix(r.URL.Path, "/inventory") {
		snapshotID, _ = requestDetails["product_id"].(string)
	}
	var before []byte
	if validID(snapshotID) {
		if e := tx.QueryRow(r.Context(), "SELECT to_jsonb(p) FROM products p WHERE store_id=$1 AND id=$2", store, snapshotID).Scan(&before); e != nil && !errors.Is(e, pgx.ErrNoRows) {
			return e
		}
	}
	result, entity, err := fn(tx)
	if err != nil {
		return err
	}
	response, err = json.Marshal(result)
	if err != nil {
		return err
	}
	_, err = tx.Exec(r.Context(), "INSERT INTO sync_operations(store_id,command_id,actor_id,request_hash,response) VALUES($1,$2,$3,$4,$5)", store, key, user(r), hash, response)
	if err != nil {
		return err
	}
	// Customer contacts and invitation addresses do not enter the immutable audit payload.
	if strings.Contains(r.URL.Path, "/customers") {
		delete(requestDetails, "name")
		delete(requestDetails, "phone")
	}
	delete(requestDetails, "email")
	delete(requestDetails, "token")
	if strings.HasSuffix(r.URL.Path, "/products") {
		snapshotID = entity
	}
	var after []byte
	if validID(snapshotID) {
		if e := tx.QueryRow(r.Context(), "SELECT to_jsonb(p) FROM products p WHERE store_id=$1 AND id=$2", store, snapshotID).Scan(&after); e != nil && !errors.Is(e, pgx.ErrNoRows) {
			return e
		}
	}
	details := map[string]any{"path": r.URL.Path, "request": requestDetails}
	if reason := r.Header.Get("X-Offline-Resolution"); reason != "" && len(reason) <= 500 {
		details["resolution"] = reason
	}
	if len(before) > 0 {
		details["before"] = json.RawMessage(before)
	}
	if len(after) > 0 {
		details["after"] = json.RawMessage(after)
	}
	encoded, _ := json.Marshal(details)
	_, err = tx.Exec(r.Context(), "INSERT INTO audit_logs(store_id,actor_id,action,entity_id,command_id,details) VALUES($1,$2,$3,$4,$5,$6)", store, user(r), r.Method+" "+chi.RouteContext(r.Context()).RoutePattern()+resolutionAudit(r), entity, key, encoded)
	if err != nil {
		return err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 200, result)
	return nil
}

type bucket struct {
	count int
	until time.Time
}
type limiter struct {
	sync.Mutex
	entries map[string]bucket
}

func (s *Server) authLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip, _, _ := net.SplitHostPort(r.RemoteAddr)
		now := time.Now()
		l := s.limiter
		l.Lock()
		for k, v := range l.entries {
			if now.After(v.until) {
				delete(l.entries, k)
			}
		}
		b := l.entries[ip]
		if b.until.IsZero() {
			b.until = now.Add(time.Minute)
		}
		b.count++
		l.entries[ip] = b
		l.Unlock()
		if b.count > 12 {
			w.Header().Set("Retry-After", "60")
			write(w, 429, map[string]string{"error": "rate_limited"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func resolutionAudit(r *http.Request) string {
	if reason := strings.TrimSpace(r.Header.Get("X-Offline-Resolution")); reason != "" && len(reason) <= 500 {
		return " [offline resolution: " + reason + "]"
	}
	return ""
}
