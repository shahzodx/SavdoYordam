package httpapi

import (
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"net/http"
	"time"
)

func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Password string `json:"password"`
		Confirm  string `json:"confirm"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if len(p.Password) > 72 || p.Confirm != "DELETE" {
		return fail(400, "invalid_request")
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	// Lock owned stores first, matching the normal command order. Deletion is
	// refused while another employee or an active offline lease can still write.
	rows, err := tx.Query(r.Context(), "SELECT s.id::text FROM stores s JOIN store_members m ON m.store_id=s.id WHERE m.user_id=$1 AND m.role='owner' ORDER BY s.id FOR UPDATE OF s", user(r))
	if err != nil {
		return err
	}
	stores := []string{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		stores = append(stores, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	var hash string
	if err = tx.QueryRow(r.Context(), "SELECT password_hash FROM users WHERE id=$1 FOR UPDATE", user(r)).Scan(&hash); err != nil {
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(p.Password)) != nil {
		return fail(401, "invalid_credentials")
	}
	for _, store := range stores {
		var blocked bool
		if err = tx.QueryRow(r.Context(), "SELECT EXISTS(SELECT 1 FROM store_members WHERE store_id=$1 AND user_id<>$2) OR EXISTS(SELECT 1 FROM offline_leases WHERE store_id=$1 AND expires_at>$3)", store, user(r), time.Now()).Scan(&blocked); err != nil {
			return err
		}
		if blocked {
			return fail(409, "deletion_blocked")
		}
		if _, err = tx.Exec(r.Context(), "UPDATE customers SET name='Deleted customer',phone='' WHERE store_id=$1", store); err != nil {
			return err
		}
		if _, err = tx.Exec(r.Context(), "UPDATE staff_invitations SET revoked=true,email='deleted@invalid.local' WHERE store_id=$1", store); err != nil {
			return err
		}
		if _, err = tx.Exec(r.Context(), "UPDATE stores SET archived=true,name='Archived store' WHERE id=$1", store); err != nil {
			return err
		}
	}
	if _, err = tx.Exec(r.Context(), "DELETE FROM push_devices WHERE actor_id=$1", user(r)); err != nil {
		return err
	}
	id := uuid.NewString()
	if _, err = tx.Exec(r.Context(), "INSERT INTO account_deletions(id,user_id) VALUES($1,$2)", id, user(r)); err != nil {
		return err
	}
	if _, err = tx.Exec(r.Context(), "DELETE FROM sessions WHERE user_id=$1", user(r)); err != nil {
		return err
	}
	if _, err = tx.Exec(r.Context(), "DELETE FROM store_members WHERE user_id=$1", user(r)); err != nil {
		return err
	}
	if _, err = tx.Exec(r.Context(), "UPDATE users SET email=$2,password_hash='deleted',deleted_at=now() WHERE id=$1", user(r), id+"@deleted.invalid"); err != nil {
		return err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	write(w, 200, map[string]any{"id": id, "account_deleted": true, "financial_history_retained": true})
	return nil
}
