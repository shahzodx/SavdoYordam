package httpapi

import (
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"net/http"
	"savdoyordam/api/internal/domain"
)

func (s *Server) customerPayment(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Amount int64  `json:"amount"`
		Method string `json:"method"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	customer := chi.URLParam(r, "customer")
	if !validID(customer) || p.Amount < 1 || p.Amount > domain.MaxMoney || !validMethod(p.Method) {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, false, func(tx pgx.Tx) (any, string, error) {
		store := chi.URLParam(r, "store")
		var debt int64
		if err := tx.QueryRow(r.Context(), "SELECT coalesce(sum(amount),0)::bigint FROM debt_entries WHERE store_id=$1 AND customer_id=$2", store, customer).Scan(&debt); err != nil {
			return nil, "", err
		}
		if p.Amount > debt {
			return nil, "", fail(409, "overpayment")
		}
		rows, err := tx.Query(r.Context(), `SELECT s.id::text,s.total-coalesce((SELECT sum(total) FROM returns WHERE store_id=s.store_id AND sale_id=s.id),0)-coalesce((SELECT sum(amount) FROM payments WHERE store_id=s.store_id AND sale_id=s.id),0) AS debt FROM sales s WHERE s.store_id=$1 AND s.customer_id=$2 ORDER BY s.created_at,s.id`, store, customer)
		if err != nil {
			return nil, "", err
		}
		type allocation struct {
			id     string
			amount int64
		}
		allocations := []allocation{}
		remaining := p.Amount
		for rows.Next() {
			var id string
			var owing int64
			if err = rows.Scan(&id, &owing); err != nil {
				rows.Close()
				return nil, "", err
			}
			if owing > 0 && remaining > 0 {
				amount := min(remaining, owing)
				allocations = append(allocations, allocation{id, amount})
				remaining -= amount
			}
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return nil, "", err
		}
		if remaining != 0 {
			return nil, "", fail(409, "data_conflict")
		}
		commandID := uuid.NewString()
		for _, a := range allocations {
			if _, err = tx.Exec(r.Context(), "INSERT INTO payments(id,store_id,sale_id,amount,method,kind) VALUES($1,$2,$3,$4,$5,'repayment')", uuid.NewString(), store, a.id, a.amount, p.Method); err != nil {
				return nil, "", err
			}
			if _, err = tx.Exec(r.Context(), "INSERT INTO debt_entries(id,store_id,customer_id,sale_id,amount,kind) VALUES($1,$2,$3,$4,$5,'repayment')", uuid.NewString(), store, customer, a.id, -a.amount); err != nil {
				return nil, "", err
			}
		}
		return map[string]any{"id": commandID, "paid": p.Amount, "debt": debt - p.Amount}, commandID, nil
	})
}
