package httpapi

import (
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"net/http"
	"strings"
	"time"
)

func (s *Server) voidExpense(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Reason string `json:"reason"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	expense := chi.URLParam(r, "expense")
	p.Reason = strings.TrimSpace(p.Reason)
	if !validID(expense) || p.Reason == "" || len(p.Reason) > 500 {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		store := chi.URLParam(r, "store")
		var amount int64
		if err := tx.QueryRow(r.Context(), "SELECT amount FROM expenses WHERE store_id=$1 AND id=$2", store, expense).Scan(&amount); err != nil {
			return nil, "", err
		}
		id := uuid.NewString()
		tz, _ := time.LoadLocation("Asia/Tashkent")
		_, err := tx.Exec(r.Context(), "INSERT INTO expense_voids(id,store_id,expense_id,amount,reason,occurred_on,actor_id) VALUES($1,$2,$3,$4,$5,$6,$7)", id, store, expense, amount, p.Reason, time.Now().In(tz).Format("2006-01-02"), user(r))
		return map[string]any{"id": id, "voided": true}, id, err
	})
}
