package httpapi

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (s *Server) requireOwner(r *http.Request) error {
	var role string
	if err := s.DB.QueryRow(r.Context(), "SELECT role FROM store_members WHERE store_id=$1 AND user_id=$2", chi.URLParam(r, "store"), user(r)).Scan(&role); err != nil {
		return err
	}
	if role != "owner" {
		return fail(403, "permission_denied")
	}
	return nil
}
func (s *Server) members(w http.ResponseWriter, r *http.Request) error {
	if err := s.requireOwner(r); err != nil {
		return err
	}
	return s.list(w, r, "SELECT m.user_id AS id,u.email,m.role FROM store_members m JOIN users u ON u.id=m.user_id WHERE m.store_id=$1 ORDER BY m.role,u.email", chi.URLParam(r, "store"))
}
func (s *Server) invitations(w http.ResponseWriter, r *http.Request) error {
	if err := s.requireOwner(r); err != nil {
		return err
	}
	return s.list(w, r, "SELECT id,email,expires_at,accepted_by,revoked FROM staff_invitations WHERE store_id=$1 ORDER BY created_at DESC LIMIT 200", chi.URLParam(r, "store"))
}
func (s *Server) invite(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Email string `json:"email"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Email = strings.ToLower(strings.TrimSpace(p.Email))
	addr, err := mail.ParseAddress(p.Email)
	if err != nil || addr.Address != p.Email || len(p.Email) > 254 {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		id := uuid.NewString()
		b := make([]byte, 32)
		if _, err := rand.Read(b); err != nil {
			return nil, "", err
		}
		token := base64.RawURLEncoding.EncodeToString(b)
		expires := time.Now().Add(7 * 24 * time.Hour)
		_, err := tx.Exec(r.Context(), "INSERT INTO staff_invitations(id,store_id,email,token_hash,expires_at,created_by) VALUES($1,$2,$3,$4,$5,$6)", id, chi.URLParam(r, "store"), p.Email, digest([]byte(token)), expires, user(r))
		return map[string]any{"id": id, "token": token, "email": p.Email, "expires_at": expires}, id, err
	})
}
func (s *Server) revokeInvite(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Reason string `json:"reason"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	id := chi.URLParam(r, "invitation")
	if !validID(id) {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		tag, err := tx.Exec(r.Context(), "UPDATE staff_invitations SET revoked=true WHERE store_id=$1 AND id=$2", chi.URLParam(r, "store"), id)
		if err == nil && tag.RowsAffected() == 0 {
			return nil, "", fail(404, "not_found")
		}
		return map[string]bool{"ok": true}, id, err
	})
}
func (s *Server) removeMember(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Reason string `json:"reason"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	id := chi.URLParam(r, "member")
	if !validID(id) || strings.TrimSpace(p.Reason) == "" || len(p.Reason) > 500 {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		tag, err := tx.Exec(r.Context(), "DELETE FROM store_members WHERE store_id=$1 AND user_id=$2 AND role='cashier'", chi.URLParam(r, "store"), id)
		if err == nil && tag.RowsAffected() == 0 {
			return nil, "", fail(409, "permission_denied")
		}
		return map[string]bool{"ok": true}, id, err
	})
}
func (s *Server) acceptInvite(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Token string `json:"token"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if len(p.Token) != 43 {
		return fail(400, "invalid_invitation")
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	var store, id, email, name string
	var accepted *string
	var expires time.Time
	var revoked bool
	hash := digest([]byte(p.Token))
	if err = tx.QueryRow(r.Context(), "SELECT store_id::text FROM staff_invitations WHERE token_hash=$1", hash).Scan(&store); errors.Is(err, pgx.ErrNoRows) {
		return fail(400, "invalid_invitation")
	} else if err != nil {
		return err
	}
	if err = tx.QueryRow(r.Context(), "SELECT name FROM stores WHERE id=$1 AND NOT archived FOR UPDATE", store).Scan(&name); err != nil {
		return err
	}
	err = tx.QueryRow(r.Context(), "SELECT id::text,email,accepted_by::text,expires_at,revoked FROM staff_invitations WHERE token_hash=$1 FOR UPDATE", hash).Scan(&id, &email, &accepted, &expires, &revoked)
	if err != nil {
		return err
	}
	var ownEmail string
	if err = tx.QueryRow(r.Context(), "SELECT email FROM users WHERE id=$1", user(r)).Scan(&ownEmail); err != nil {
		return err
	}
	if email != ownEmail || revoked || time.Now().After(expires) {
		return fail(400, "invalid_invitation")
	}
	if accepted != nil {
		var exists bool
		if err = tx.QueryRow(r.Context(), "SELECT EXISTS(SELECT 1 FROM store_members WHERE store_id=$1 AND user_id=$2)", store, user(r)).Scan(&exists); err != nil {
			return err
		}
		if *accepted != user(r) || !exists {
			return fail(409, "invalid_invitation")
		}
	} else {
		if _, err = tx.Exec(r.Context(), "INSERT INTO store_members(store_id,user_id,role) VALUES($1,$2,'cashier') ON CONFLICT DO NOTHING", store, user(r)); err != nil {
			return err
		}
		if _, err = tx.Exec(r.Context(), "UPDATE staff_invitations SET accepted_by=$2 WHERE id=$1", id, user(r)); err != nil {
			return err
		}
		if _, err = tx.Exec(r.Context(), "INSERT INTO audit_logs(store_id,actor_id,action,entity_id,command_id) VALUES($1,$2,'accept invitation',$3,$3)", store, user(r), id); err != nil {
			return err
		}
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 200, map[string]string{"id": store, "name": name})
	return nil
}
