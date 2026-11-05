package httpapi

import (
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"net/http"
	"savdoyordam/api/internal/domain"
	"time"
)

type saleInput struct {
	CustomerID *string     `json:"customer_id"`
	Paid       int64       `json:"paid"`
	Method     string      `json:"method"`
	Items      []lineInput `json:"items"`
	OccurredAt *time.Time  `json:"occurred_at,omitempty"`
}
type lineInput struct {
	ProductID     string `json:"product_id"`
	Quantity      int64  `json:"quantity"`
	ExpectedPrice int64  `json:"expected_price"`
	Discount      int64  `json:"discount,omitempty"`
}
type pricedLine struct {
	lineInput
	Name, Unit          string
	Price, Total, Stock int64
	Cost                *int64
}

func validMethod(s string) bool { return s == "cash" || s == "card" }
func (s *Server) createSale(w http.ResponseWriter, r *http.Request) error {
	var p saleInput
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if len(p.Items) < 1 || len(p.Items) > 100 || p.Paid < 0 || p.Paid > domain.MaxMoney || !validMethod(p.Method) || (p.CustomerID != nil && !validID(*p.CustomerID)) {
		return fail(400, "invalid_sale")
	}
	if p.OccurredAt != nil && (r.Header.Get("X-Offline-Lease") == "" || p.OccurredAt.After(time.Now().Add(5*time.Minute)) || p.OccurredAt.Before(time.Now().Add(-30*24*time.Hour))) {
		return fail(400, "invalid_sale")
	}
	seen := map[string]bool{}
	for _, l := range p.Items {
		if !validID(l.ProductID) || l.Quantity < 1 || l.Quantity > domain.MaxQuantity || l.Discount < 0 || l.Discount > domain.MaxMoney || seen[l.ProductID] {
			return fail(400, "invalid_sale")
		}
		seen[l.ProductID] = true
	}
	return s.command(w, r, p, false, func(tx pgx.Tx) (any, string, error) {
		store := chi.URLParam(r, "store")
		created := time.Now().UTC()
		if p.OccurredAt != nil {
			created = *p.OccurredAt
			if r.Header.Get("X-Offline-Resolution") == "" {
				var start, end time.Time
				if err := tx.QueryRow(r.Context(), "SELECT created_at,expires_at FROM offline_leases WHERE store_id=$1 AND id::text=$2", store, r.Header.Get("X-Offline-Lease")).Scan(&start, &end); err != nil {
					return nil, "", err
				}
				if created.Before(start.Add(-5*time.Minute)) || created.After(end) {
					return nil, "", fail(400, "invalid_sale")
				}
			}
		}
		lines := []pricedLine{}
		var total int64
		for _, l := range p.Items {
			if l.Discount > 0 {
				var role string
				if err := tx.QueryRow(r.Context(), "SELECT role FROM store_members WHERE store_id=$1 AND user_id=$2", store, user(r)).Scan(&role); err != nil {
					return nil, "", err
				}
				if role != "owner" {
					return nil, "", fail(403, "permission_denied")
				}
				break
			}
		}
		if p.CustomerID != nil {
			var id string
			if err := tx.QueryRow(r.Context(), "SELECT id::text FROM customers WHERE store_id=$1 AND id=$2", store, *p.CustomerID).Scan(&id); err != nil {
				return nil, "", err
			}
		}
		for _, input := range p.Items {
			l := pricedLine{lineInput: input}
			err := tx.QueryRow(r.Context(), "SELECT name,unit,price,cost,stock FROM products WHERE store_id=$1 AND id=$2 AND NOT archived", store, l.ProductID).Scan(&l.Name, &l.Unit, &l.Price, &l.Cost, &l.Stock)
			if err != nil {
				return nil, "", err
			}
			if l.Price != l.ExpectedPrice {
				return nil, "", fail(409, "price_changed")
			}
			if l.Stock < l.Quantity {
				return nil, "", fail(409, "insufficient_stock")
			}
			if l.Unit == "piece" && l.Quantity%1000 != 0 {
				return nil, "", fail(400, "invalid_quantity")
			}
			l.Total, err = domain.LineTotal(l.Price, l.Quantity)
			if err != nil {
				return nil, "", fail(400, "amount_limit")
			}
			if l.Discount >= l.Total && l.Discount > 0 {
				return nil, "", fail(400, "invalid_sale")
			}
			l.Total -= l.Discount
			if total > domain.MaxMoney-l.Total {
				return nil, "", fail(400, "amount_limit")
			}
			total += l.Total
			lines = append(lines, l)
		}
		if p.Paid > total {
			return nil, "", fail(400, "overpayment")
		}
		if p.Paid < total && p.CustomerID == nil {
			return nil, "", fail(400, "customer_required")
		}
		id := uuid.NewString()
		_, err := tx.Exec(r.Context(), "INSERT INTO sales(id,store_id,customer_id,total,created_by,created_at) VALUES($1,$2,$3,$4,$5,$6)", id, store, p.CustomerID, total, user(r), created)
		if err != nil {
			return nil, "", err
		}
		for _, l := range lines {
			_, err = tx.Exec(r.Context(), "INSERT INTO sale_items(store_id,sale_id,product_id,name,quantity,price,cost,total,discount) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)", store, id, l.ProductID, l.Name, l.Quantity, l.Price, l.Cost, l.Total, l.Discount)
			if err != nil {
				return nil, "", err
			}
			_, err = tx.Exec(r.Context(), "UPDATE products SET stock=stock-$3,version=version+1 WHERE store_id=$1 AND id=$2", store, l.ProductID, l.Quantity)
			if err != nil {
				return nil, "", err
			}
			_, err = tx.Exec(r.Context(), "INSERT INTO inventory_movements(id,store_id,product_id,quantity,reason,sale_id,created_at) VALUES($1,$2,$3,$4,'sale',$5,$6)", uuid.NewString(), store, l.ProductID, -l.Quantity, id, created)
			if err != nil {
				return nil, "", err
			}
		}
		if p.Paid > 0 {
			_, err = tx.Exec(r.Context(), "INSERT INTO payments(id,store_id,sale_id,amount,method,kind,created_at) VALUES($1,$2,$3,$4,$5,'sale',$6)", uuid.NewString(), store, id, p.Paid, p.Method, created)
			if err != nil {
				return nil, "", err
			}
		}
		if p.Paid < total {
			_, err = tx.Exec(r.Context(), "INSERT INTO debt_entries(id,store_id,customer_id,sale_id,amount,kind,created_at) VALUES($1,$2,$3,$4,$5,'sale',$6)", uuid.NewString(), store, *p.CustomerID, id, total-p.Paid, created)
			if err != nil {
				return nil, "", err
			}
		}
		return map[string]any{"id": id, "total": total, "paid": p.Paid, "debt": total - p.Paid}, id, nil
	})
}
func (s *Server) sales(w http.ResponseWriter, r *http.Request) error {
	limit, offset := page(r)
	customer := r.URL.Query().Get("customer_id")
	if customer != "" && !validID(customer) {
		return fail(400, "invalid_request")
	}
	return s.list(w, r, `SELECT s.id,s.customer_id,c.name AS customer_name,s.total,s.created_at,
 coalesce((SELECT sum(p.amount) FROM payments p WHERE p.store_id=s.store_id AND p.sale_id=s.id),0)::bigint AS paid,
 coalesce((SELECT sum(total) FROM returns rt WHERE rt.store_id=s.store_id AND rt.sale_id=s.id),0)>=s.total AS returned,
 coalesce((SELECT sum(total) FROM returns rt WHERE rt.store_id=s.store_id AND rt.sale_id=s.id),0)::bigint AS returned_total
 FROM sales s LEFT JOIN customers c ON c.store_id=s.store_id AND c.id=s.customer_id
 WHERE s.store_id=$1 AND ($2='' OR s.customer_id::text=$2) ORDER BY s.created_at DESC,s.id LIMIT $3 OFFSET $4`, chi.URLParam(r, "store"), customer, limit, offset)
}
func (s *Server) saleDetail(w http.ResponseWriter, r *http.Request) error {
	if !validID(chi.URLParam(r, "sale")) {
		return fail(400, "invalid_request")
	}
	return s.list(w, r, `SELECT i.product_id,i.name,i.quantity,i.price,i.total,i.discount,p.unit,coalesce((SELECT sum(ri.quantity) FROM return_items ri WHERE ri.store_id=i.store_id AND ri.sale_id=i.sale_id AND ri.product_id=i.product_id),0)::bigint AS returned_quantity FROM sale_items i JOIN products p ON p.store_id=i.store_id AND p.id=i.product_id WHERE i.store_id=$1 AND i.sale_id=$2 ORDER BY i.name`, chi.URLParam(r, "store"), chi.URLParam(r, "sale"))
}
func (s *Server) repay(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Amount int64  `json:"amount"`
		Method string `json:"method"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if !validID(chi.URLParam(r, "sale")) || p.Amount < 1 || p.Amount > domain.MaxMoney || !validMethod(p.Method) {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, false, func(tx pgx.Tx) (any, string, error) {
		store, sale := chi.URLParam(r, "store"), chi.URLParam(r, "sale")
		var customer *string
		var total, paid int64
		var returned bool
		err := tx.QueryRow(r.Context(), `SELECT customer_id::text,total-coalesce((SELECT sum(total) FROM returns WHERE store_id=$1 AND sale_id=$2),0)::bigint,coalesce((SELECT sum(amount) FROM payments WHERE store_id=$1 AND sale_id=$2),0)::bigint,coalesce((SELECT sum(total) FROM returns WHERE store_id=$1 AND sale_id=$2),0)>=sales.total FROM sales WHERE store_id=$1 AND id=$2`, store, sale).Scan(&customer, &total, &paid, &returned)
		if err != nil {
			return nil, "", err
		}
		if returned {
			return nil, "", fail(409, "sale_returned")
		}
		if customer == nil || p.Amount > total-paid {
			return nil, "", fail(409, "overpayment")
		}
		id := uuid.NewString()
		_, err = tx.Exec(r.Context(), "INSERT INTO payments(id,store_id,sale_id,amount,method,kind) VALUES($1,$2,$3,$4,$5,'repayment')", id, store, sale, p.Amount, p.Method)
		if err != nil {
			return nil, "", err
		}
		_, err = tx.Exec(r.Context(), "INSERT INTO debt_entries(id,store_id,customer_id,sale_id,amount,kind) VALUES($1,$2,$3,$4,$5,'repayment')", uuid.NewString(), store, *customer, sale, -p.Amount)
		return map[string]any{"id": id, "debt": total - paid - p.Amount}, id, err
	})
}
