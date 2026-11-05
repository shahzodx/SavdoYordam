package httpapi

import (
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"net/http"
	"savdoyordam/api/internal/domain"
	"strconv"
	"strings"
	"time"
)

// Rows are encoded with database column names; numeric columns remain integers.
func (s *Server) list(w http.ResponseWriter, r *http.Request, query string, args ...any) error {
	rows, err := s.DB.Query(r.Context(), query, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	items := []map[string]any{}
	fields := rows.FieldDescriptions()
	for rows.Next() {
		v, err := rows.Values()
		if err != nil {
			return err
		}
		item := map[string]any{}
		for i, f := range fields {
			value := v[i]
			if id, ok := value.([16]byte); ok {
				value = uuid.UUID(id).String()
			}
			item[f.Name] = value
		}
		items = append(items, item)
	}
	if err = rows.Err(); err != nil {
		return err
	}
	write(w, 200, items)
	return nil
}
func page(r *http.Request) (int, int) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit < 1 || limit > 200 {
		limit = 100
	}
	if offset < 0 || offset > 1000000 {
		offset = 0
	}
	return limit, offset
}
func (s *Server) products(w http.ResponseWriter, r *http.Request) error {
	limit, offset := page(r)
	return s.list(w, r, "SELECT id,name,sku,unit,price,cost,stock,minimum_stock,version,category,archived FROM products WHERE store_id=$1 AND (NOT archived OR $5) AND (strpos(lower(name),lower($2))>0 OR strpos(lower(sku),lower($2))>0) ORDER BY lower(name),id LIMIT $3 OFFSET $4", chi.URLParam(r, "store"), r.URL.Query().Get("q"), limit, offset, r.URL.Query().Get("archived") == "true")
}

type productInput struct {
	Name     string `json:"name"`
	SKU      string `json:"sku"`
	Unit     string `json:"unit"`
	Price    int64  `json:"price"`
	Cost     *int64 `json:"cost"`
	Stock    int64  `json:"stock"`
	Minimum  int64  `json:"minimum_stock"`
	Category string `json:"category,omitempty"`
}

func (s *Server) createProduct(w http.ResponseWriter, r *http.Request) error {
	var p productInput
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Name = strings.TrimSpace(p.Name)
	p.SKU = strings.TrimSpace(p.SKU)
	p.Category = strings.TrimSpace(p.Category)
	if len(p.Category) > 80 || p.Name == "" || len(p.Name) > 160 || p.SKU == "" || len(p.SKU) > 80 || (p.Unit != "piece" && p.Unit != "kg" && p.Unit != "liter") || p.Price < 1 || p.Price > domain.MaxMoney || p.Stock < 0 || p.Stock > domain.MaxQuantity || p.Minimum < 0 || p.Minimum > domain.MaxQuantity || (p.Unit == "piece" && p.Stock%1000 != 0) || (p.Cost != nil && (*p.Cost < 0 || *p.Cost > domain.MaxMoney)) {
		return fail(400, "invalid_product")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		id := uuid.NewString()
		store := chi.URLParam(r, "store")
		_, err := tx.Exec(r.Context(), "INSERT INTO products(id,store_id,name,sku,unit,price,cost,stock,minimum_stock,category) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", id, store, p.Name, p.SKU, p.Unit, p.Price, p.Cost, p.Stock, p.Minimum, p.Category)
		if err != nil {
			return nil, "", err
		}
		if p.Stock > 0 {
			_, err = tx.Exec(r.Context(), "INSERT INTO inventory_movements(id,store_id,product_id,quantity,reason) VALUES($1,$2,$3,$4,'opening')", uuid.NewString(), store, id, p.Stock)
		}
		return map[string]any{"id": id, "name": p.Name, "stock": p.Stock}, id, err
	})
}
func (s *Server) adjustInventory(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		ProductID string `json:"product_id"`
		Quantity  int64  `json:"quantity"`
		Reason    string `json:"reason"`
		Version   int64  `json:"version"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if !validID(p.ProductID) || p.Quantity == 0 || p.Quantity > domain.MaxQuantity || p.Quantity < -domain.MaxQuantity || strings.TrimSpace(p.Reason) == "" || len(p.Reason) > 500 {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		var stock, version int64
		var unit string
		store := chi.URLParam(r, "store")
		err := tx.QueryRow(r.Context(), "SELECT stock,version,unit FROM products WHERE store_id=$1 AND id=$2", store, p.ProductID).Scan(&stock, &version, &unit)
		if err != nil {
			return nil, "", err
		}
		if version != p.Version {
			return nil, "", fail(409, "version_conflict")
		}
		if stock+p.Quantity < 0 || stock+p.Quantity > domain.MaxQuantity || (unit == "piece" && p.Quantity%1000 != 0) {
			return nil, "", fail(409, "invalid_stock")
		}
		_, err = tx.Exec(r.Context(), "UPDATE products SET stock=stock+$3,version=version+1 WHERE store_id=$1 AND id=$2", store, p.ProductID, p.Quantity)
		if err != nil {
			return nil, "", err
		}
		_, err = tx.Exec(r.Context(), "INSERT INTO inventory_movements(id,store_id,product_id,quantity,reason) VALUES($1,$2,$3,$4,$5)", uuid.NewString(), store, p.ProductID, p.Quantity, p.Reason)
		return map[string]any{"id": p.ProductID, "stock": stock + p.Quantity, "version": version + 1}, p.ProductID, err
	})
}
func (s *Server) inventory(w http.ResponseWriter, r *http.Request) error {
	limit, offset := page(r)
	if !validID(chi.URLParam(r, "product")) {
		return fail(400, "invalid_request")
	}
	return s.list(w, r, "SELECT id,quantity,reason,sale_id,created_at FROM inventory_movements WHERE store_id=$1 AND product_id=$2 ORDER BY created_at DESC,id LIMIT $3 OFFSET $4", chi.URLParam(r, "store"), chi.URLParam(r, "product"), limit, offset)
}
func (s *Server) customers(w http.ResponseWriter, r *http.Request) error {
	limit, offset := page(r)
	return s.list(w, r, "SELECT c.id,c.name,c.phone,coalesce(sum(d.amount),0)::bigint AS debt FROM customers c LEFT JOIN debt_entries d ON d.store_id=c.store_id AND d.customer_id=c.id WHERE c.store_id=$1 AND strpos(lower(c.name),lower($2))>0 GROUP BY c.id ORDER BY lower(c.name),c.id LIMIT $3 OFFSET $4", chi.URLParam(r, "store"), r.URL.Query().Get("q"), limit, offset)
}
func (s *Server) createCustomer(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Name  string `json:"name"`
		Phone string `json:"phone"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	p.Name = strings.TrimSpace(p.Name)
	if p.Name == "" || len(p.Name) > 160 || len(p.Phone) > 30 {
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, false, func(tx pgx.Tx) (any, string, error) {
		id := uuid.NewString()
		_, err := tx.Exec(r.Context(), "INSERT INTO customers(id,store_id,name,phone) VALUES($1,$2,$3,$4)", id, chi.URLParam(r, "store"), p.Name, p.Phone)
		return map[string]string{"id": id, "name": p.Name}, id, err
	})
}
func (s *Server) customerLedger(w http.ResponseWriter, r *http.Request) error {
	if !validID(chi.URLParam(r, "customer")) {
		return fail(400, "invalid_request")
	}
	limit, offset := page(r)
	return s.list(w, r, "SELECT id,sale_id,amount,kind,created_at FROM debt_entries WHERE store_id=$1 AND customer_id=$2 ORDER BY created_at DESC,id LIMIT $3 OFFSET $4", chi.URLParam(r, "store"), chi.URLParam(r, "customer"), limit, offset)
}
func (s *Server) expenses(w http.ResponseWriter, r *http.Request) error {
	limit, offset := page(r)
	return s.list(w, r, "SELECT e.id,e.amount,e.category,e.description,e.method,e.occurred_on,EXISTS(SELECT 1 FROM expense_voids v WHERE v.expense_id=e.id) AS voided FROM expenses e WHERE e.store_id=$1 ORDER BY e.occurred_on DESC,e.id LIMIT $2 OFFSET $3", chi.URLParam(r, "store"), limit, offset)
}
func (s *Server) createExpense(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Amount      int64  `json:"amount"`
		Category    string `json:"category,omitempty"`
		Description string `json:"description"`
		Method      string `json:"method"`
		Date        string `json:"occurred_on"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	date, err := time.Parse("2006-01-02", p.Date)
	if err != nil || date.Year() < 2000 || date.Year() > 2100 || p.Amount < 1 || p.Amount > domain.MaxMoney || len(p.Description) > 500 || !validMethod(p.Method) {
		return fail(400, "invalid_request")
	}
	switch p.Category {
	case "rent", "salary", "delivery", "utilities", "other":
	default:
		return fail(400, "invalid_request")
	}
	return s.command(w, r, p, true, func(tx pgx.Tx) (any, string, error) {
		id := uuid.NewString()
		_, err := tx.Exec(r.Context(), "INSERT INTO expenses(id,store_id,amount,category,description,method,occurred_on) VALUES($1,$2,$3,$4,$5,$6,$7)", id, chi.URLParam(r, "store"), p.Amount, p.Category, p.Description, p.Method, date)
		return map[string]string{"id": id}, id, err
	})
}
