package httpapi

import (
	"encoding/json"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
	"net/http"
	"strings"
)

func (s *Server) storeSettings(w http.ResponseWriter, r *http.Request) error {
	var name, retail, role, email string
	err := s.DB.QueryRow(r.Context(), "SELECT s.name,s.retail_type,m.role,u.email FROM stores s JOIN store_members m ON m.store_id=s.id JOIN users u ON u.id=m.user_id WHERE s.id=$1 AND m.user_id=$2", chi.URLParam(r, "store"), user(r)).Scan(&name, &retail, &role, &email)
	if err != nil {
		return err
	}
	write(w, 200, map[string]string{"name": name, "retail_type": retail, "role": role, "email": email, "currency": "UZS", "timezone": "Asia/Tashkent"})
	return nil
}
func (s *Server) editStoreSettings(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Name       string `json:"name"`
		RetailType string `json:"retail_type"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Name = strings.TrimSpace(p.Name)
	valid := map[string]bool{"general": true, "grocery": true, "clothing": true, "household": true, "other": true}
	if p.Name == "" || len(p.Name) > 100 || !valid[p.RetailType] {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		id := chi.URLParam(r, "store")
		_, err := tx.Exec(r.Context(), "UPDATE stores SET name=$2,retail_type=$3 WHERE id=$1", id, p.Name, p.RetailType)
		return map[string]any{"id": id, "name": p.Name, "retail_type": p.RetailType}, id, err
	})
}
func (s *Server) exportStore(w http.ResponseWriter, r *http.Request) error {
	if err := s.requireOwner(r); err != nil {
		return err
	}
	tx, err := s.DB.BeginTx(r.Context(), pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	result := map[string]any{"format": "savdoyordam-export-v1", "currency": "UZS", "money_unit": "tiyin", "quantity_scale": 1000}
	for _, table := range []string{"products", "customers", "sales", "sale_items", "returns", "return_items", "payments", "debt_entries", "inventory_movements", "expenses", "expense_voids", "purchases", "purchase_items", "audit_logs"} {
		var raw []byte
		// Table identifiers come exclusively from this fixed allowlist.
		if err = tx.QueryRow(r.Context(), "SELECT coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) FROM "+table+" t WHERE store_id=$1", chi.URLParam(r, "store")).Scan(&raw); err != nil {
			return err
		}
		result[table] = json.RawMessage(raw)
	}
	var raw []byte
	if err = tx.QueryRow(r.Context(), "SELECT to_jsonb(s) FROM stores s WHERE id=$1", chi.URLParam(r, "store")).Scan(&raw); err != nil {
		return err
	}
	result["store"] = json.RawMessage(raw)
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 200, result)
	return nil
}
func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Current string `json:"current_password"`
		Next    string `json:"new_password"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if len(p.Current) > 72 || len(p.Next) < 12 || len(p.Next) > 72 {
		return fail(400, "invalid_credentials")
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	var hash string
	if err = tx.QueryRow(r.Context(), "SELECT password_hash FROM users WHERE id=$1 FOR UPDATE", user(r)).Scan(&hash); err != nil {
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(p.Current)) != nil {
		return fail(401, "invalid_credentials")
	}
	next, err := bcrypt.GenerateFromPassword([]byte(p.Next), 12)
	if err != nil {
		return err
	}
	if _, err = tx.Exec(r.Context(), "UPDATE users SET password_hash=$2 WHERE id=$1", user(r), string(next)); err != nil {
		return err
	}
	if _, err = tx.Exec(r.Context(), "DELETE FROM sessions WHERE user_id=$1 AND token_hash<>$2", user(r), digest([]byte(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")))); err != nil {
		return err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 200, map[string]bool{"ok": true})
	return nil
}
func (s *Server) sessions(w http.ResponseWriter, r *http.Request) error {
	return s.list(w, r, "SELECT token_hash AS id,created_at,expires_at,(token_hash=$2) AS current FROM sessions WHERE user_id=$1 AND expires_at>now() ORDER BY created_at DESC", user(r), digest([]byte(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))))
}
func (s *Server) revokeSession(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		ID string `json:"id"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if len(p.ID) != 64 {
		return fail(400, "invalid_request")
	}
	_, err := s.DB.Exec(r.Context(), "DELETE FROM sessions WHERE user_id=$1 AND token_hash=$2", user(r), p.ID)
	if err != nil {
		return err
	}
	write(w, 200, map[string]bool{"ok": true})
	return nil
}

func (s *Server) audit(w http.ResponseWriter, r *http.Request) error {
	if err := s.requireOwner(r); err != nil {
		return err
	}
	limit, offset := page(r)
	return s.list(w, r, "SELECT a.id,a.action,a.entity_id,a.created_at,a.details,u.email AS actor FROM audit_logs a JOIN users u ON u.id=a.actor_id WHERE a.store_id=$1 ORDER BY a.created_at DESC,a.id DESC LIMIT $2 OFFSET $3", chi.URLParam(r, "store"), limit, offset)
}
