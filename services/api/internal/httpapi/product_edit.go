package httpapi

import (
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"net/http"
	"savdoyordam/api/internal/domain"
	"strings"
)

func (s *Server) editProduct(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Name     string  `json:"name"`
		SKU      string  `json:"sku"`
		Price    int64   `json:"price"`
		Cost     *int64  `json:"cost"`
		Minimum  int64   `json:"minimum_stock"`
		Version  int64   `json:"version"`
		Category *string `json:"category,omitempty"`
		Archived *bool   `json:"archived,omitempty"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Name = strings.TrimSpace(p.Name)
	p.SKU = strings.TrimSpace(p.SKU)
	if p.Category != nil && len(*p.Category) > 80 {
		return fail(400, "invalid_product")
	}
	if !validID(chi.URLParam(r, "product")) || p.Name == "" || len(p.Name) > 160 || p.SKU == "" || len(p.SKU) > 80 || p.Price < 1 || p.Price > domain.MaxMoney || p.Minimum < 0 || p.Minimum > domain.MaxQuantity || p.Version < 1 || (p.Cost != nil && (*p.Cost < 0 || *p.Cost > domain.MaxMoney)) {
		return fail(400, "invalid_product")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		id := chi.URLParam(r, "product")
		store := chi.URLParam(r, "store")
		var version int64
		if err := tx.QueryRow(r.Context(), "SELECT version FROM products WHERE store_id=$1 AND id=$2", store, id).Scan(&version); err != nil {
			return nil, "", err
		}
		if version != p.Version {
			return nil, "", fail(409, "version_conflict")
		}
		_, err := tx.Exec(r.Context(), "UPDATE products SET name=$3,sku=$4,price=$5,cost=$6,minimum_stock=$7,category=coalesce($8,category),archived=coalesce($9,archived),version=version+1 WHERE store_id=$1 AND id=$2", store, id, p.Name, p.SKU, p.Price, p.Cost, p.Minimum, p.Category, p.Archived)
		return map[string]any{"id": id, "version": version + 1}, id, err
	})
}
