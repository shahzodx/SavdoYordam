package httpapi

import (
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"math/big"
	"net/http"
	"savdoyordam/api/internal/domain"
	"strings"
)

// Cumulative allocation avoids losing or duplicating a tiyin across repeated partial returns.
func prorata(total, part, whole int64) int64 {
	value := new(big.Int).Mul(big.NewInt(total), big.NewInt(part))
	value.Add(value, big.NewInt(whole/2))
	value.Div(value, big.NewInt(whole))
	return value.Int64()
}

type returnLineInput struct {
	ProductID string `json:"product_id"`
	Quantity  int64  `json:"quantity"`
}

func (s *Server) returnSale(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Reason string            `json:"reason"`
		Items  []returnLineInput `json:"items,omitempty"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Reason = strings.TrimSpace(p.Reason)
	if !validID(chi.URLParam(r, "sale")) || p.Reason == "" || len(p.Reason) > 500 || len(p.Items) > 100 || (p.Items != nil && len(p.Items) == 0) {
		return fail(400, "invalid_request")
	}
	requested := map[string]int64{}
	for _, l := range p.Items {
		if !validID(l.ProductID) || l.Quantity <= 0 || l.Quantity > domain.MaxQuantity || requested[l.ProductID] != 0 {
			return fail(400, "invalid_quantity")
		}
		requested[l.ProductID] = l.Quantity
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		store, sale := chi.URLParam(r, "store"), chi.URLParam(r, "sale")
		var original, paid, previous int64
		var customer *string
		err := tx.QueryRow(r.Context(), `SELECT total,customer_id::text,coalesce((SELECT sum(amount) FROM payments WHERE store_id=$1 AND sale_id=$2),0)::bigint,coalesce((SELECT sum(total) FROM returns WHERE store_id=$1 AND sale_id=$2),0)::bigint FROM sales WHERE store_id=$1 AND id=$2`, store, sale).Scan(&original, &customer, &paid, &previous)
		if err != nil {
			return nil, "", err
		}
		if previous >= original {
			return nil, "", fail(409, "sale_returned")
		}
		rows, err := tx.Query(r.Context(), `SELECT i.product_id::text,i.quantity,i.total,i.cost,p.unit,p.stock,p.cost,coalesce((SELECT sum(ri.quantity) FROM return_items ri WHERE ri.store_id=i.store_id AND ri.sale_id=i.sale_id AND ri.product_id=i.product_id),0)::bigint FROM sale_items i JOIN products p ON p.store_id=i.store_id AND p.id=i.product_id WHERE i.store_id=$1 AND i.sale_id=$2`, store, sale)
		if err != nil {
			return nil, "", err
		}
		type line struct {
			id              string
			quantity, total int64
			cost            *int64
			newCost         *int64
		}
		lines := []line{}
		var refundTotal int64
		for rows.Next() {
			var id, unit string
			var qty, total, stock, returned int64
			var cost, currentCost *int64
			if err = rows.Scan(&id, &qty, &total, &cost, &unit, &stock, &currentCost, &returned); err != nil {
				rows.Close()
				return nil, "", err
			}
			q := requested[id]
			if len(p.Items) == 0 {
				q = qty - returned
			}
			if q == 0 {
				continue
			}
			if q > qty-returned || stock > domain.MaxQuantity-q || unit == "piece" && q%1000 != 0 {
				rows.Close()
				return nil, "", fail(409, "invalid_quantity")
			}
			amount := prorata(total, returned+q, qty) - prorata(total, returned, qty)
			if amount <= 0 {
				rows.Close()
				return nil, "", fail(400, "invalid_quantity")
			}
			var costAmount *int64
			if cost != nil {
				full := prorata(*cost, qty, 1000)
				v := prorata(full, returned+q, qty) - prorata(full, returned, qty)
				costAmount = &v
			}
			var newCost *int64
			if cost != nil {
				newCost = weightedCost(stock, currentCost, q, *cost)
			}
			lines = append(lines, line{id, q, amount, costAmount, newCost})
			refundTotal += amount
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return nil, "", err
		}
		if len(lines) == 0 || len(p.Items) > 0 && len(lines) != len(p.Items) {
			return nil, "", fail(409, "invalid_quantity")
		}
		id := uuid.NewString()
		if _, err = tx.Exec(r.Context(), "INSERT INTO returns(id,store_id,sale_id,reason,total) VALUES($1,$2,$3,$4,$5)", id, store, sale, p.Reason, refundTotal); err != nil {
			return nil, "", err
		}
		debt := original - previous - paid
		cancelled := min(debt, refundTotal)
		cashRefund := refundTotal - cancelled
		// Cancel outstanding debt first; refund any remaining amount against existing tenders, cash then card.
		if cancelled > 0 && customer != nil {
			if _, err = tx.Exec(r.Context(), "INSERT INTO debt_entries(id,store_id,customer_id,sale_id,amount,kind) VALUES($1,$2,$3,$4,$5,'return')", uuid.NewString(), store, *customer, sale, -cancelled); err != nil {
				return nil, "", err
			}
		}
		remaining := cashRefund
		for _, method := range []string{"cash", "card"} {
			var available int64
			if err = tx.QueryRow(r.Context(), "SELECT coalesce(sum(amount),0)::bigint FROM payments WHERE store_id=$1 AND sale_id=$2 AND method=$3", store, sale, method).Scan(&available); err != nil {
				return nil, "", err
			}
			amount := min(remaining, available)
			if amount <= 0 {
				continue
			}
			if _, err = tx.Exec(r.Context(), "INSERT INTO payments(id,store_id,sale_id,amount,method,kind) VALUES($1,$2,$3,$4,$5,'refund')", uuid.NewString(), store, sale, -amount, method); err != nil {
				return nil, "", err
			}
			remaining -= amount
		}
		if remaining != 0 {
			return nil, "", fail(409, "data_conflict")
		}
		for _, l := range lines {
			if _, err = tx.Exec(r.Context(), "INSERT INTO return_items(store_id,return_id,sale_id,product_id,quantity,total,cost_total) VALUES($1,$2,$3,$4,$5,$6,$7)", store, id, sale, l.id, l.quantity, l.total, l.cost); err != nil {
				return nil, "", err
			}
			if _, err = tx.Exec(r.Context(), "UPDATE products SET stock=stock+$3,cost=$4,version=version+1 WHERE store_id=$1 AND id=$2", store, l.id, l.quantity, l.newCost); err != nil {
				return nil, "", err
			}
			if _, err = tx.Exec(r.Context(), "INSERT INTO inventory_movements(id,store_id,product_id,quantity,reason,sale_id) VALUES($1,$2,$3,$4,'return',$5)", uuid.NewString(), store, l.id, l.quantity, sale); err != nil {
				return nil, "", err
			}
		}
		return map[string]any{"id": id, "total": refundTotal, "refunded": cashRefund, "debt_cancelled": cancelled}, id, nil
	})
}
