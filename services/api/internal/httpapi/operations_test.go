package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"net/http/httptest"
	"testing"
)

func (f *fixture) deviceCall(path string, p any, key, device, lease string, resolution ...string) (int, []byte) {
	raw, _ := json.Marshal(p)
	r := httptest.NewRequest("POST", f.path(path), bytes.NewReader(raw))
	r.Header.Set("Authorization", "Bearer "+f.token)
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Idempotency-Key", key)
	r.Header.Set("X-Device-ID", device)
	r.Header.Set("X-Offline-Lease", lease)
	if len(resolution) > 0 {
		r.Header.Set("X-Offline-Resolution", resolution[0])
	}
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	return w.Code, w.Body.Bytes()
}
func TestPurchasesAndInvitations(t *testing.T) {
	f := setup(t)
	p := f.product(1000)
	key := uuid.NewString()
	body := map[string]any{"supplier": "Supplier", "note": "Delivery", "items": []any{map[string]any{"product_id": p, "quantity": 2000, "unit_cost": 900000}}}
	purchase := f.ok("POST", f.path("/purchases"), body, key)
	number(t, purchase, "total", 1800000)
	f.ok("POST", f.path("/purchases"), body, key)
	var stock, cost int64
	if err := f.db.QueryRow(context.Background(), "SELECT stock,cost FROM products WHERE id=$1", p).Scan(&stock, &cost); err != nil || stock != 3000 || cost != 800000 {
		t.Fatalf("stock/cost: %d/%d %v", stock, cost, err)
	}
	report := f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "expenses", 0)
	if _, err := f.db.Exec(context.Background(), "DELETE FROM purchases WHERE id=$1", purchase["id"]); err == nil {
		t.Fatal("purchase history mutable")
	}
	owner := f.token
	employee := f.ok("POST", "/v1/auth/register", map[string]any{"email": "cashier@example.test", "password": "correct horse battery staple"}, "")
	invitation := f.ok("POST", f.path("/invitations"), map[string]any{"email": "cashier@example.test"}, uuid.NewString())
	f.token = employee["token"].(string)
	f.ok("POST", "/v1/invitations/accept", map[string]any{"token": invitation["token"]}, "")
	f.ok("POST", "/v1/invitations/accept", map[string]any{"token": invitation["token"]}, "")
	if status, _ := f.call("POST", f.path("/purchases"), body, uuid.NewString()); status != 403 {
		t.Fatalf("cashier purchase status %d", status)
	}
	if status, _ := f.call("GET", f.path("/members"), nil, ""); status != 403 {
		t.Fatalf("cashier member list status %d", status)
	}
	f.token = owner
	f.ok("POST", f.path("/members/"+employee["user_id"].(string)+"/remove"), map[string]any{"reason": "Owner revoked access"}, uuid.NewString())
	f.token = employee["token"].(string)
	if status, _ := f.call("GET", f.path("/products"), nil, ""); status != 404 {
		t.Fatal("revoked employee retained access")
	}
	if status, _ := f.call("POST", "/v1/invitations/accept", map[string]any{"token": invitation["token"]}, ""); status != 409 {
		t.Fatal("used invitation recreated revoked membership")
	}
}
func TestOfflineLeaseSerializesStock(t *testing.T) {
	f := setup(t)
	p := f.product(3000)
	device := uuid.NewString()
	status, b := f.deviceCall("/offline/enable", map[string]any{"device_id": device, "hours": 8}, uuid.NewString(), device, "")
	if status != 200 {
		t.Fatalf("enable: %d %s", status, b)
	}
	var lease map[string]any
	if err := json.Unmarshal(b, &lease); err != nil {
		t.Fatal(err)
	}
	id := lease["id"].(string)
	sale := basket(p, 1000, 1000000, nil)
	key := uuid.NewString()
	if status, b = f.deviceCall("/sales", sale, uuid.NewString(), uuid.NewString(), ""); status != 409 {
		t.Fatalf("other device sold: %d %s", status, b)
	}
	if status, b = f.deviceCall("/inventory", map[string]any{"product_id": p, "quantity": 1000, "version": 1, "reason": "delivery"}, uuid.NewString(), device, id); status != 409 {
		t.Fatalf("catalog changed during lease: %d %s", status, b)
	}
	if status, b = f.deviceCall("/sales", sale, key, device, id); status != 200 {
		t.Fatalf("lease sale: %d %s", status, b)
	}
	if status, b = f.deviceCall("/sales", sale, key, device, id); status != 200 {
		t.Fatalf("lease replay: %d %s", status, b)
	}
	var stock int64
	if err := f.db.QueryRow(context.Background(), "SELECT stock FROM products WHERE id=$1", p).Scan(&stock); err != nil || stock != 2000 {
		t.Fatalf("duplicate sale: %d %v", stock, err)
	}
	if _, err := f.db.Exec(context.Background(), "UPDATE offline_leases SET expires_at=now()-interval '1 second' WHERE store_id=$1", f.store); err != nil {
		t.Fatal(err)
	}
	if status, _ = f.deviceCall("/sales", sale, uuid.NewString(), device, id); status != 409 {
		t.Fatal("expired offline sale silently accepted")
	}
	if status, b = f.deviceCall("/sales", sale, key, device, id); status != 200 {
		t.Fatalf("expired acknowledged replay: %d %s", status, b)
	}
}
func TestWeightedCost(t *testing.T) {
	c := int64(600000)
	if got := weightedCost(1000, &c, 2000, 900000); got == nil || *got != 800000 {
		t.Fatal(got)
	}
	if weightedCost(1000, nil, 1000, 900000) != nil {
		t.Fatal("unknown previous cost invented")
	}
	if got := weightedCost(0, nil, 1000, 900000); got == nil || *got != 900000 {
		t.Fatal(got)
	}
}

func TestPartialReturnsPreserveMoneyAndStock(t *testing.T) {
	f := setup(t)
	p := f.product(3000)
	customer := f.ok("POST", f.path("/customers"), map[string]any{"name": "Ali", "phone": ""}, uuid.NewString())["id"]
	saleInput := basket(p, 3000, 1000000, customer)
	saleInput["items"].([]any)[0].(map[string]any)["discount"] = 300000
	sale := f.ok("POST", f.path("/sales"), saleInput, uuid.NewString())
	number(t, sale, "total", 2700000)
	id := sale["id"].(string)
	body := map[string]any{"reason": "One unit returned", "items": []any{map[string]any{"product_id": p, "quantity": 1000}}}
	key := uuid.NewString()
	ret := f.ok("POST", f.path("/sales/"+id+"/return"), body, key)
	number(t, ret, "total", 900000)
	number(t, ret, "debt_cancelled", 900000)
	number(t, ret, "refunded", 0)
	f.ok("POST", f.path("/sales/"+id+"/return"), body, key)
	report := f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "net_sales", 1800000)
	number(t, report, "outstanding_debt", 800000)
	number(t, report, "gross_profit", 600000)
	f.ok("POST", f.path("/sales/"+id+"/payments"), map[string]any{"amount": 800000, "method": "card"}, uuid.NewString())
	ret = f.ok("POST", f.path("/sales/"+id+"/return"), body, uuid.NewString())
	number(t, ret, "refunded", 900000)
	ret = f.ok("POST", f.path("/sales/"+id+"/return"), body, uuid.NewString())
	number(t, ret, "refunded", 900000)
	if status, _ := f.call("POST", f.path("/sales/"+id+"/return"), body, uuid.NewString()); status != 409 {
		t.Fatal("returned more than purchased")
	}
	report = f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "net_sales", 0)
	number(t, report, "outstanding_debt", 0)
	number(t, report, "received", 0)
	number(t, report, "gross_profit", 0)
	var stock int64
	if err := f.db.QueryRow(context.Background(), "SELECT stock FROM products WHERE id=$1", p).Scan(&stock); err != nil || stock != 3000 {
		t.Fatalf("stock %d %v", stock, err)
	}
}
func TestProrataAllocatesRemainder(t *testing.T) {
	if prorata(101, 333, 1000) != 34 || prorata(101, 666, 1000) != 67 || prorata(101, 1000, 1000) != 101 {
		t.Fatal("partial returns lose rounding remainder")
	}
	if prorata(1000000000000, 1000000000, 1000) != 1000000000000000000 {
		t.Fatal("allocation overflow")
	}
}

func TestAnalyticsCustomerPaymentAndExpenseVoid(t *testing.T) {
	f := setup(t)
	p := f.product(3000)
	customer := f.ok("POST", f.path("/customers"), map[string]any{"name": "Ali", "phone": ""}, uuid.NewString())["id"].(string)
	f.ok("POST", f.path("/sales"), basket(p, 1000, 0, customer), uuid.NewString())
	f.ok("POST", f.path("/sales"), basket(p, 1000, 0, customer), uuid.NewString())
	key := uuid.NewString()
	body := map[string]any{"amount": 1500000, "method": "cash"}
	payment := f.ok("POST", f.path("/customers/"+customer+"/payments"), body, key)
	number(t, payment, "debt", 500000)
	f.ok("POST", f.path("/customers/"+customer+"/payments"), body, key)
	report := f.ok("GET", f.path("/dashboard"), nil, "")
	number(t, report, "received", 1500000)
	number(t, report, "outstanding_debt", 500000)
	analytics := f.ok("GET", f.path("/analytics"), nil, "")
	products := analytics["products"].([]any)
	if len(products) != 1 {
		t.Fatal(products)
	}
	number(t, products[0].(map[string]any), "total", 2000000)
	exp := f.ok("POST", f.path("/expenses"), map[string]any{"amount": 100000, "category": "rent", "description": "Rent", "method": "cash", "occurred_on": report["from"]}, uuid.NewString())
	f.ok("POST", f.path("/expenses/"+exp["id"].(string)+"/void"), map[string]any{"reason": "Entry error"}, uuid.NewString())
	number(t, f.ok("GET", f.path("/dashboard"), nil, ""), "expenses", 0)
	export := f.ok("GET", f.path("/export"), nil, "")
	if len(export["sales"].([]any)) != 2 || len(export["expense_voids"].([]any)) != 1 {
		t.Fatal("incomplete export")
	}
}
func TestAccountSecurityAndDeletion(t *testing.T) {
	f := setup(t)
	oldToken := f.token
	logged := f.ok("POST", "/v1/auth/login", map[string]any{"email": "owner@example.test", "password": "correct horse battery staple"}, "")
	f.token = logged["token"].(string)
	f.ok("POST", "/v1/auth/password", map[string]any{"current_password": "correct horse battery staple", "new_password": "new correct horse battery staple"}, "")
	f.token = oldToken
	if status, _ := f.call("GET", "/v1/stores", nil, ""); status != 401 {
		t.Fatal("old session still active")
	}
	f.token = logged["token"].(string)
	f.ok("POST", "/v1/auth/delete", map[string]any{"password": "new correct horse battery staple", "confirm": "DELETE"}, "")
	if status, _ := f.call("GET", "/v1/stores", nil, ""); status != 401 {
		t.Fatal("deleted user session still active")
	}
	if status, _ := f.call("POST", "/v1/auth/login", map[string]any{"email": "owner@example.test", "password": "new correct horse battery staple"}, ""); status != 401 {
		t.Fatal("deleted user can log in")
	}
	var archived bool
	if err := f.db.QueryRow(context.Background(), "SELECT archived FROM stores WHERE id=$1", f.store).Scan(&archived); err != nil || !archived {
		t.Fatal("store not archived", err)
	}
}

func TestReturnRestoresHistoricalCostIntoNewStock(t *testing.T) {
	f := setup(t)
	p := f.product(1000)
	sale := f.ok("POST", f.path("/sales"), basket(p, 1000, 1000000, nil), uuid.NewString())
	f.ok("POST", f.path("/purchases"), map[string]any{"supplier": "New lot", "note": "", "items": []any{map[string]any{"product_id": p, "quantity": 1000, "unit_cost": 900000}}}, uuid.NewString())
	f.ok("POST", f.path("/sales/"+sale["id"].(string)+"/return"), map[string]any{"reason": "Return original unit"}, uuid.NewString())
	var cost int64
	if err := f.db.QueryRow(context.Background(), "SELECT cost FROM products WHERE id=$1", p).Scan(&cost); err != nil || cost != 750000 {
		t.Fatalf("returned stock valued at %d: %v", cost, err)
	}
}

func TestAuditCapturesProductChangesAndRedactsContacts(t *testing.T) {
	f := setup(t)
	p := f.product(1000)
	f.ok("POST", f.path("/products/"+p), map[string]any{"name": "New name", "sku": uuid.NewString(), "price": 2000000, "cost": 600000, "minimum_stock": 1000, "version": 1}, uuid.NewString())
	f.ok("POST", f.path("/customers"), map[string]any{"name": "Private customer", "phone": "+998901234567"}, uuid.NewString())
	var before, after int64
	if err := f.db.QueryRow(context.Background(), "SELECT (details->'before'->>'price')::bigint,(details->'after'->>'price')::bigint FROM audit_logs WHERE entity_id=$1 AND details ? 'before'", p).Scan(&before, &after); err != nil || before != 1000000 || after != 2000000 {
		t.Fatalf("missing audit snapshot %d %d %v", before, after, err)
	}
	var leak bool
	if err := f.db.QueryRow(context.Background(), "SELECT EXISTS(SELECT 1 FROM audit_logs WHERE details::text LIKE '%+998901234567%' OR details::text LIKE '%Private customer%')").Scan(&leak); err != nil || leak {
		t.Fatal("immutable audit retained customer contacts", err)
	}
}
