package httpapi

import (
	"math/big"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"savdoyordam/api/internal/domain"
)

func (s *Server) purchases(w http.ResponseWriter, r *http.Request) error {
	if err := s.requireOwner(r); err != nil {
		return err
	}
	limit, offset := page(r)
	return s.list(w, r, "SELECT id,supplier,note,total,created_at FROM purchases WHERE store_id=$1 ORDER BY created_at DESC,id LIMIT $2 OFFSET $3", chi.URLParam(r, "store"), limit, offset)
}
func (s *Server) purchaseDetail(w http.ResponseWriter, r *http.Request) error {
	if err := s.requireOwner(r); err != nil {
		return err
	}
	id := chi.URLParam(r, "purchase")
	if !validID(id) {
		return fail(400, "invalid_request")
	}
	return s.list(w, r, "SELECT product_id,name,quantity,unit_cost,total FROM purchase_items WHERE store_id=$1 AND purchase_id=$2 ORDER BY name", chi.URLParam(r, "store"), id)
}

type purchaseLine struct {
	ProductID string `json:"product_id"`
	Quantity  int64  `json:"quantity"`
	Cost      int64  `json:"unit_cost"`
}

func weightedCost(stock int64, old *int64, quantity, cost int64) *int64 {
	if stock > 0 && old == nil {
		return nil
	}
	if old == nil {
		old = &cost
	}
	value := new(big.Int).Mul(big.NewInt(stock), big.NewInt(*old))
	value.Add(value, new(big.Int).Mul(big.NewInt(quantity), big.NewInt(cost)))
	denominator := big.NewInt(stock + quantity)
	value.Add(value, new(big.Int).Div(new(big.Int).Set(denominator), big.NewInt(2)))
	value.Div(value, denominator)
	result := value.Int64()
	return &result
}
func (s *Server) createPurchase(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Supplier string         `json:"supplier"`
		Note     string         `json:"note"`
		Items    []purchaseLine `json:"items"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Supplier = strings.TrimSpace(p.Supplier)
	p.Note = strings.TrimSpace(p.Note)
	if len(p.Supplier) > 160 || len(p.Note) > 500 || len(p.Items) < 1 || len(p.Items) > 100 {
		return fail(400, "invalid_request")
	}
	seen := map[string]bool{}
	for _, l := range p.Items {
		if !validID(l.ProductID) || l.Quantity <= 0 || l.Quantity > domain.MaxQuantity || l.Cost <= 0 || l.Cost > domain.MaxMoney || seen[l.ProductID] {
			return fail(400, "invalid_product")
		}
		seen[l.ProductID] = true
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		store := chi.URLParam(r, "store")
		id := uuid.NewString()
		var total int64
		type priced struct {
			purchaseLine
			name  string
			total int64
		}
		lines := []priced{}
		for _, l := range p.Items {
			var name, unit string
			var stock int64
			var cost *int64
			err := tx.QueryRow(r.Context(), "SELECT name,unit,stock,cost FROM products WHERE store_id=$1 AND id=$2 AND NOT archived", store, l.ProductID).Scan(&name, &unit, &stock, &cost)
			if err != nil {
				return nil, "", err
			}
			if stock > domain.MaxQuantity-l.Quantity || unit == "piece" && l.Quantity%1000 != 0 {
				return nil, "", fail(400, "invalid_quantity")
			}
			amount, err := domain.LineTotal(l.Cost, l.Quantity)
			if err != nil || total > domain.MaxMoney-amount {
				return nil, "", fail(400, "amount_limit")
			}
			total += amount
			if _, err = tx.Exec(r.Context(), "UPDATE products SET stock=stock+$3,cost=$4,version=version+1 WHERE store_id=$1 AND id=$2", store, l.ProductID, l.Quantity, weightedCost(stock, cost, l.Quantity, l.Cost)); err != nil {
				return nil, "", err
			}
			lines = append(lines, priced{l, name, amount})
		}
		if _, err := tx.Exec(r.Context(), "INSERT INTO purchases(id,store_id,supplier,note,total,created_by) VALUES($1,$2,$3,$4,$5,$6)", id, store, p.Supplier, p.Note, total, user(r)); err != nil {
			return nil, "", err
		}
		for _, l := range lines {
			if _, err := tx.Exec(r.Context(), "INSERT INTO purchase_items(store_id,purchase_id,product_id,name,quantity,unit_cost,total) VALUES($1,$2,$3,$4,$5,$6,$7)", store, id, l.ProductID, l.name, l.Quantity, l.Cost, l.total); err != nil {
				return nil, "", err
			}
			if _, err := tx.Exec(r.Context(), "INSERT INTO inventory_movements(id,store_id,product_id,quantity,reason) VALUES($1,$2,$3,$4,'purchase')", uuid.NewString(), store, l.ProductID, l.Quantity); err != nil {
				return nil, "", err
			}
		}
		return map[string]any{"id": id, "total": total}, id, nil
	})
}
