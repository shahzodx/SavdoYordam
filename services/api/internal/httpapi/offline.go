package httpapi

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// The store row is locked before this check. While a lease is active, only its
// actor/device may sell and all other inventory mutations are frozen.
func (s *Server) enforceLease(r *http.Request, tx pgx.Tx) error {
	var id, device, actor string
	var expires time.Time
	err := tx.QueryRow(r.Context(), "SELECT id::text,device_id::text,actor_id::text,expires_at FROM offline_leases WHERE store_id=$1", chi.URLParam(r, "store")).Scan(&id, &device, &actor, &expires)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	supplied := r.Header.Get("X-Offline-Lease")
	resolution := strings.TrimSpace(r.Header.Get("X-Offline-Resolution"))
	if supplied != "" && resolution != "" && (err != nil || !time.Now().Before(expires)) {
		if len(resolution) > 500 {
			return fail(400, "invalid_request")
		}
		var role string
		if e := tx.QueryRow(r.Context(), "SELECT role FROM store_members WHERE store_id=$1 AND user_id=$2", chi.URLParam(r, "store"), user(r)).Scan(&role); e != nil {
			return e
		}
		if role != "owner" {
			return fail(403, "permission_denied")
		}
		// This remains an ordinary sale transaction: current stock, prices and
		// customer are revalidated. The original UUID and body remain unchanged.
		return nil
	}

	if supplied != "" && (err != nil || supplied != id || !time.Now().Before(expires) || r.Header.Get("X-Device-ID") != device || user(r) != actor) {
		return fail(409, "offline_lease_expired")
	}
	if err != nil || !time.Now().Before(expires) {
		return nil
	}
	path := strings.TrimPrefix(r.URL.Path, "/v1/stores/"+chi.URLParam(r, "store"))
	if path == "/sales" {
		if supplied != id || r.Header.Get("X-Device-ID") != device || user(r) != actor {
			return fail(409, "offline_store_locked")
		}
		return nil
	}
	if strings.HasPrefix(path, "/products") || path == "/inventory" || path == "/purchases" || strings.HasSuffix(path, "/return") {
		return fail(409, "offline_store_locked")
	}
	return nil
}
func (s *Server) offlineStatus(w http.ResponseWriter, r *http.Request) error {
	var id, device, actor string
	var expires time.Time
	err := s.DB.QueryRow(r.Context(), "SELECT id::text,device_id::text,actor_id::text,expires_at FROM offline_leases WHERE store_id=$1", chi.URLParam(r, "store")).Scan(&id, &device, &actor, &expires)
	if errors.Is(err, pgx.ErrNoRows) {
		write(w, 200, map[string]bool{"active": false})
		return nil
	}
	if err != nil {
		return err
	}
	write(w, 200, map[string]any{"active": time.Now().Before(expires), "id": id, "device_id": device, "actor_id": actor, "expires_at": expires, "server_time": time.Now().UTC()})
	return nil
}
func (s *Server) enableOffline(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Device string `json:"device_id"`
		Hours  int    `json:"hours"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if !validID(p.Device) || p.Device != r.Header.Get("X-Device-ID") || p.Hours < 1 || p.Hours > 24 {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		store := chi.URLParam(r, "store")
		var device string
		var expires time.Time
		err := tx.QueryRow(r.Context(), "SELECT device_id::text,expires_at FROM offline_leases WHERE store_id=$1", store).Scan(&device, &expires)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return nil, "", err
		}
		if err == nil && time.Now().Before(expires) && device != p.Device {
			return nil, "", fail(409, "offline_store_locked")
		}
		id := uuid.NewString()
		expires = time.Now().Add(time.Duration(p.Hours) * time.Hour)
		_, err = tx.Exec(r.Context(), "INSERT INTO offline_leases(store_id,id,device_id,actor_id,expires_at) VALUES($1,$2,$3,$4,$5) ON CONFLICT(store_id) DO UPDATE SET id=EXCLUDED.id,device_id=EXCLUDED.device_id,actor_id=EXCLUDED.actor_id,expires_at=EXCLUDED.expires_at,created_at=now()", store, id, p.Device, user(r), expires)
		return map[string]any{"id": id, "active": true, "device_id": p.Device, "actor_id": user(r), "expires_at": expires, "server_time": time.Now().UTC()}, id, err
	})
}
func (s *Server) disableOffline(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Reason string `json:"reason"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if strings.TrimSpace(p.Reason) == "" || len(p.Reason) > 500 {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		store := chi.URLParam(r, "store")
		_, err := tx.Exec(r.Context(), "DELETE FROM offline_leases WHERE store_id=$1", store)
		return map[string]bool{"active": false}, store, err
	})
}
