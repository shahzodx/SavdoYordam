package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

type fixture struct {
	t            *testing.T
	h            http.Handler
	db           *pgxpool.Pool
	token, store string
}

func setup(t *testing.T) *fixture {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL required for PostgreSQL integration")
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	name := "savdo_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	if _, err = admin.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		t.Fatal(err)
	}
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		t.Fatal(err)
	}
	cfg.ConnConfig.Database = name
	db, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		db.Close()
		_, e := admin.Exec(ctx, "DROP DATABASE "+name+" WITH (FORCE)")
		admin.Close()
		if e != nil {
			t.Error(e)
		}
	})
	sqlDB := stdlib.OpenDB(*cfg.ConnConfig)
	defer sqlDB.Close()
	goose.SetLogger(goose.NopLogger())
	if err = goose.SetDialect("postgres"); err != nil {
		t.Fatal(err)
	}
	if err = goose.Up(sqlDB, filepath.Join("..", "..", "migrations")); err != nil {
		t.Fatal(err)
	}
	f := &fixture{t: t, db: db, h: New(db, slog.New(slog.NewJSONHandler(io.Discard, nil)))}
	result := f.ok("POST", "/v1/auth/register", map[string]any{"email": "owner@example.test", "password": "correct horse battery staple"}, "")
	f.token = result["token"].(string)
	f.store = uuid.NewString()
	f.ok("POST", "/v1/stores", map[string]any{"id": f.store, "name": "Sinov do‘koni"}, "")
	return f
}
func (f *fixture) call(method, path string, p any, key string) (int, []byte) {
	raw, _ := json.Marshal(p)
	r := httptest.NewRequest(method, path, bytes.NewReader(raw))
	r.Header.Set("Authorization", "Bearer "+f.token)
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Idempotency-Key", key)
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	return w.Code, w.Body.Bytes()
}
func (f *fixture) ok(method, path string, p any, key string) map[string]any {
	f.t.Helper()
	status, b := f.call(method, path, p, key)
	if status >= 300 {
		f.t.Fatalf("%s %s: %d %s", method, path, status, b)
	}
	var v map[string]any
	if err := json.Unmarshal(b, &v); err != nil {
		f.t.Fatal(err)
	}
	return v
}
func (f *fixture) path(s string) string { return "/v1/stores/" + f.store + s }
func (f *fixture) product(stock int) string {
	return f.ok("POST", f.path("/products"), map[string]any{"name": "Guruch", "sku": uuid.NewString(), "unit": "kg", "price": 1000000, "cost": 600000, "stock": stock, "minimum_stock": 1000}, uuid.NewString())["id"].(string)
}
func basket(product string, qty, paid int, customer any) map[string]any {
	return map[string]any{"customer_id": customer, "paid": paid, "method": "cash", "items": []any{map[string]any{"product_id": product, "quantity": qty, "expected_price": 1000000}}}
}
func number(t *testing.T, v map[string]any, key string, want int64) {
	t.Helper()
	if v[key] != float64(want) {
		t.Fatalf("%s = %v, want %d", key, v[key], want)
	}
}
func TestCommerceLifecycle(t *testing.T) {
	f := setup(t)
	p := f.product(3000)
	customer := f.ok("POST", f.path("/customers"), map[string]any{"name": "Ali", "phone": ""}, uuid.NewString())["id"]
	key := uuid.NewString()
	input := basket(p, 1500, 500000, customer)
	sale := f.ok("POST", f.path("/sales"), input, key)
	id := sale["id"].(string)
	number(t, sale, "total", 1500000)
	number(t, sale, "debt", 1000000)
	replay := f.ok("POST", f.path("/sales"), input, key)
	if replay["id"] != id {
		t.Fatal("duplicate sale")
	}
	input["paid"] = 600000
	if status, _ := f.call("POST", f.path("/sales"), input, key); status != 409 {
		t.Fatal("payload mismatch accepted")
	}
	payKey := uuid.NewString()
	payment := map[string]any{"amount": 400000, "method": "card"}
	f.ok("POST", f.path("/sales/"+id+"/payments"), payment, payKey)
	f.ok("POST", f.path("/sales/"+id+"/payments"), payment, payKey)
	report := f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "sales", 1500000)
	number(t, report, "received", 900000)
	number(t, report, "outstanding_debt", 600000)
	number(t, report, "gross_profit", 600000)
	if status, _ := f.call("POST", f.path("/sales/"+id+"/payments"), map[string]any{"amount": 600001, "method": "cash"}, uuid.NewString()); status != 409 {
		t.Fatal("overpayment accepted")
	}
	f.ok("POST", f.path("/sales/"+id+"/payments"), map[string]any{"amount": 600000, "method": "cash"}, uuid.NewString())
	f.ok("POST", f.path("/expenses"), map[string]any{"amount": 100000, "category": "rent", "description": "Ijara", "method": "cash", "occurred_on": report["from"]}, uuid.NewString())
	retKey := uuid.NewString()
	ret := map[string]any{"reason": "Customer returned the complete purchase"}
	f.ok("POST", f.path("/sales/"+id+"/return"), ret, retKey)
	f.ok("POST", f.path("/sales/"+id+"/return"), ret, retKey)
	report = f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "net_sales", 0)
	number(t, report, "received", 0)
	number(t, report, "outstanding_debt", 0)
	number(t, report, "gross_profit", 0)
	number(t, report, "expenses", 100000)
	var stock int
	if err := f.db.QueryRow(context.Background(), "SELECT stock FROM products WHERE id=$1", p).Scan(&stock); err != nil || stock != 3000 {
		t.Fatalf("stock %d %v", stock, err)
	}
	if _, err := f.db.Exec(context.Background(), "UPDATE sales SET total=1 WHERE id=$1", id); err == nil {
		t.Fatal("immutable sale updated")
	}
	// A returned sale cannot receive another payment or a second return command.
	if status, _ := f.call("POST", f.path("/sales/"+id+"/return"), ret, uuid.NewString()); status != 409 {
		t.Fatal("double return")
	}
	f.ok("POST", "/v1/auth/logout", map[string]any{}, "")
	if status, _ := f.call("GET", f.path("/dashboard"), nil, ""); status != 401 {
		t.Fatal("revoked session accepted")
	}
}
func TestConcurrencyAndIsolation(t *testing.T) {
	f := setup(t)
	p := f.product(1000)
	var wg sync.WaitGroup
	results := make(chan int, 2)
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			status, _ := f.call("POST", f.path("/sales"), basket(p, 1000, 1000000, nil), uuid.NewString())
			results <- status
		}()
	}
	wg.Wait()
	close(results)
	counts := map[int]int{}
	for status := range results {
		counts[status]++
	}
	if counts[200] != 1 || counts[409] != 1 {
		t.Fatalf("last unit: %v", counts)
	}
	// Lost-response retry against a fresh handler still replays the persisted command.
	p2 := f.product(2000)
	key := uuid.NewString()
	input := basket(p2, 1000, 1000000, nil)
	first := f.ok("POST", f.path("/sales"), input, key)
	f.h = New(f.db, slog.New(slog.NewJSONHandler(io.Discard, nil)))
	second := f.ok("POST", f.path("/sales"), input, key)
	if first["id"] != second["id"] {
		t.Fatal("restart duplicated operation")
	}
	ownerToken := f.token
	other := f.ok("POST", "/v1/auth/register", map[string]any{"email": "other@example.test", "password": "correct horse battery staple"}, "")
	f.token = other["token"].(string)
	if status, _ := f.call("GET", f.path("/products"), nil, ""); status != 404 {
		t.Fatal("tenant read leak")
	}
	if status, _ := f.call("POST", f.path("/sales"), input, uuid.NewString()); status != 404 {
		t.Fatal("tenant write leak")
	}
	f.token = ownerToken
	var owner string
	if err := f.db.QueryRow(context.Background(), "SELECT user_id::text FROM store_members WHERE store_id=$1", f.store).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec(context.Background(), "UPDATE store_members SET role='cashier' WHERE store_id=$1 AND user_id=$2", f.store, owner); err != nil {
		t.Fatal(err)
	}
	if status, _ := f.call("POST", f.path("/expenses"), map[string]any{"amount": 100, "category": "other", "method": "cash", "occurred_on": "2026-11-05"}, uuid.NewString()); status != 403 {
		t.Fatal("cashier wrote owner expense")
	}
}
func TestRollbackAndDebtReturn(t *testing.T) {
	f := setup(t)
	p := f.product(1000)
	customer := f.ok("POST", f.path("/customers"), map[string]any{"name": "Vali"}, uuid.NewString())["id"]
	bad := basket(p, 2000, 2000000, nil)
	if status, _ := f.call("POST", f.path("/sales"), bad, uuid.NewString()); status != 409 {
		t.Fatal("oversell accepted")
	}
	report := f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "sale_count", 0)
	sale := f.ok("POST", f.path("/sales"), basket(p, 1000, 0, customer), uuid.NewString())
	id := sale["id"].(string)
	f.ok("POST", f.path("/sales/"+id+"/return"), map[string]any{"reason": "Unpaid purchase cancelled"}, uuid.NewString())
	report = f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "outstanding_debt", 0)
	number(t, report, "received", 0)
	status, body := f.call("GET", f.path("/reports?from=2026-11-10&to=2026-11-01"), nil, "")
	if status != 400 {
		t.Fatal(fmt.Sprint(status, string(body)))
	}
}

func TestPriceEditsAndConcurrentReplay(t *testing.T) {
	f := setup(t)
	p := f.product(5000)
	edit := map[string]any{"name": "New name", "sku": "EDITED", "price": 1200000, "cost": nil, "minimum_stock": 1000, "version": 1}
	f.ok("POST", f.path("/products/"+p), edit, uuid.NewString())
	if status, _ := f.call("POST", f.path("/products/"+p), edit, uuid.NewString()); status != 409 {
		t.Fatal("stale product edit accepted")
	}
	input := basket(p, 1000, 1000000, nil)
	if status, _ := f.call("POST", f.path("/sales"), input, uuid.NewString()); status != 409 {
		t.Fatal("old price accepted")
	}
	input["items"].([]any)[0].(map[string]any)["expected_price"] = 1200000
	input["paid"] = 1200000
	key := uuid.NewString()
	var wg sync.WaitGroup
	results := make(chan []byte, 2)
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			status, b := f.call("POST", f.path("/sales"), input, key)
			if status != 200 {
				t.Errorf("replay status %d: %s", status, b)
			}
			results <- b
		}()
	}
	wg.Wait()
	close(results)
	var ids []string
	for b := range results {
		var v map[string]any
		if err := json.Unmarshal(b, &v); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, v["id"].(string))
	}
	if ids[0] != ids[1] {
		t.Fatal("concurrent replay produced two sales")
	}
	report := f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "sale_count", 1)
	if report["gross_profit"] != nil {
		t.Fatal("profit invented without cost")
	}
	var stock int
	if err := f.db.QueryRow(context.Background(), "SELECT stock FROM products WHERE id=$1", p).Scan(&stock); err != nil || stock != 4000 {
		t.Fatalf("stock %d %v", stock, err)
	}
}

func TestAuthenticationAndCrossStoreReferences(t *testing.T) {
	f := setup(t)
	if status, _ := f.call("POST", "/v1/auth/login", map[string]any{"email": "owner@example.test", "password": "wrong password"}, ""); status != 401 {
		t.Fatal("bad password accepted")
	}
	result := f.ok("POST", "/v1/auth/login", map[string]any{"email": "owner@example.test", "password": "correct horse battery staple"}, "")
	f.token = result["token"].(string)
	first := f.store
	p := f.product(1000)
	f.store = uuid.NewString()
	f.ok("POST", "/v1/stores", map[string]any{"id": f.store, "name": "Second store"}, "")
	customer := f.ok("POST", f.path("/customers"), map[string]any{"name": "Another shop customer"}, uuid.NewString())["id"]
	f.store = first
	if status, _ := f.call("POST", f.path("/sales"), basket(p, 1000, 0, customer), uuid.NewString()); status != 404 {
		t.Fatal("cross-store customer accepted")
	}
	report := f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "sale_count", 0)
	if _, err := f.db.Exec(context.Background(), "UPDATE sessions SET expires_at=now()-interval '1 second' WHERE token_hash=$1", digest([]byte(f.token))); err != nil {
		t.Fatal(err)
	}
	if status, _ := f.call("GET", f.path("/products"), nil, ""); status != 401 {
		t.Fatal("expired session accepted")
	}
}
