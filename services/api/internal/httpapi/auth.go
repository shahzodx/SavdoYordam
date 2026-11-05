package httpapi

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
	"net/http"
	"net/mail"
	"strings"
	"time"
)

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) error {
	var c credentials
	if err := decode(w, r, &c); err != nil {
		return err
	}
	c.Email = strings.ToLower(strings.TrimSpace(c.Email))
	addr, err := mail.ParseAddress(c.Email)
	if err != nil || addr.Address != c.Email || len(c.Email) > 254 || len(c.Password) < 12 || len(c.Password) > 72 {
		return fail(400, "invalid_credentials")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(c.Password), 12)
	if err != nil {
		return err
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	id := uuid.NewString()
	_, err = tx.Exec(r.Context(), "INSERT INTO users(id,email,password_hash) VALUES($1,$2,$3)", id, c.Email, string(hash))
	if err != nil {
		return err
	}
	token, err := newSession(r, tx, id)
	if err != nil {
		return err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 201, token)
	return nil
}

// Valid bcrypt hash ensures unknown accounts do not skip the expensive comparison.
const dummyHash = "$2a$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW"

func (s *Server) login(w http.ResponseWriter, r *http.Request) error {
	var c credentials
	if err := decode(w, r, &c); err != nil {
		return err
	}
	if len(c.Password) > 72 {
		return fail(401, "invalid_credentials")
	}
	var id, hash string
	err := s.DB.QueryRow(r.Context(), "SELECT id::text,password_hash FROM users WHERE email=$1", strings.ToLower(strings.TrimSpace(c.Email))).Scan(&id, &hash)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if hash == "" {
		hash = dummyHash
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(c.Password)) != nil || id == "" {
		return fail(401, "invalid_credentials")
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	token, err := newSession(r, tx, id)
	if err != nil {
		return err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 200, token)
	return nil
}
func newSession(r *http.Request, tx pgx.Tx, id string) (any, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	token := base64.RawURLEncoding.EncodeToString(b)
	expires := time.Now().Add(7 * 24 * time.Hour)
	_, err := tx.Exec(r.Context(), "INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,$3)", digest([]byte(token)), id, expires)
	return map[string]any{"token": token, "user_id": id, "expires_at": expires}, err
}
func (s *Server) logout(w http.ResponseWriter, r *http.Request) error {
	if device := r.Header.Get("X-Device-ID"); validID(device) {
		if _, err := s.DB.Exec(r.Context(), "DELETE FROM push_devices WHERE actor_id=$1 AND device_id=$2", user(r), device); err != nil {
			return err
		}
	}

	_, err := s.DB.Exec(r.Context(), "DELETE FROM sessions WHERE token_hash=$1", digest([]byte(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))))
	if err == nil {
		write(w, 200, map[string]bool{"ok": true})
	}
	return err
}
func (s *Server) stores(w http.ResponseWriter, r *http.Request) error {
	return s.list(w, r, "SELECT s.id,s.name,m.role FROM stores s JOIN store_members m ON m.store_id=s.id WHERE m.user_id=$1 AND NOT s.archived ORDER BY s.created_at", user(r))
}
func (s *Server) createStore(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		RetailType string `json:"retail_type,omitempty"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Name = strings.TrimSpace(p.Name)
	if p.RetailType == "" {
		p.RetailType = "general"
	}
	validRetail := map[string]bool{"general": true, "grocery": true, "clothing": true, "household": true, "other": true}
	if !validRetail[p.RetailType] {
		return fail(400, "invalid_request")
	}
	if !validID(p.ID) || p.Name == "" || len(p.Name) > 100 {
		return fail(400, "invalid_request")
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	// A client-generated store UUID also makes onboarding retryable after a lost response.
	_, err = tx.Exec(r.Context(), "INSERT INTO stores(id,name,retail_type) VALUES($1,$2,$3) ON CONFLICT DO NOTHING", p.ID, p.Name, p.RetailType)
	if err != nil {
		return err
	}
	var existingName string
	var members int
	if err = tx.QueryRow(r.Context(), "SELECT name FROM stores WHERE id=$1 FOR UPDATE", p.ID).Scan(&existingName); err != nil {
		return err
	}
	if err = tx.QueryRow(r.Context(), "SELECT count(*) FROM store_members WHERE store_id=$1", p.ID).Scan(&members); err != nil {
		return err
	}
	if members > 0 {
		var owner string
		if err = tx.QueryRow(r.Context(), "SELECT user_id::text FROM store_members WHERE store_id=$1 AND role='owner'", p.ID).Scan(&owner); err != nil {
			return err
		}
		if owner != user(r) || existingName != p.Name {
			return fail(409, "data_conflict")
		}
	} else {
		_, err = tx.Exec(r.Context(), "INSERT INTO store_members(store_id,user_id,role) VALUES($1,$2,'owner')", p.ID, user(r))
		if err != nil {
			return err
		}
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 200, map[string]string{"id": p.ID, "name": p.Name, "role": "owner"})
	return nil
}
