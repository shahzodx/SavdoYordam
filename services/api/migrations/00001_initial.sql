-- +goose Up
CREATE TABLE users (
 id uuid PRIMARY KEY, email text NOT NULL UNIQUE, password_hash text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE sessions (
 token_hash text PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id),
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_idx ON sessions(user_id);
CREATE TABLE stores (
 id uuid PRIMARY KEY, name text NOT NULL CHECK(length(name) BETWEEN 1 AND 100),
 timezone text NOT NULL DEFAULT 'Asia/Tashkent', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE store_members (
 store_id uuid NOT NULL REFERENCES stores(id), user_id uuid NOT NULL REFERENCES users(id),
 role text NOT NULL CHECK(role IN ('owner','cashier')), PRIMARY KEY(store_id,user_id)
);
CREATE TABLE products (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id), name text NOT NULL,
 sku text NOT NULL, unit text NOT NULL CHECK(unit IN ('piece','kg','liter')),
 price bigint NOT NULL CHECK(price BETWEEN 1 AND 1000000000000),
 cost bigint CHECK(cost BETWEEN 0 AND 1000000000000),
 stock bigint NOT NULL CHECK(stock BETWEEN 0 AND 1000000000),
 minimum_stock bigint NOT NULL DEFAULT 0 CHECK(minimum_stock >= 0),
 version bigint NOT NULL DEFAULT 1, UNIQUE(store_id,sku), UNIQUE(store_id,id)
);
CREATE INDEX products_search_idx ON products(store_id,lower(name),id);
CREATE TABLE customers (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id), name text NOT NULL,
 phone text NOT NULL DEFAULT '', created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(store_id,id)
);
CREATE TABLE sales (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id), customer_id uuid,
 total bigint NOT NULL CHECK(total > 0), created_by uuid NOT NULL REFERENCES users(id),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(store_id,id),
 FOREIGN KEY(store_id,customer_id) REFERENCES customers(store_id,id)
);
CREATE INDEX sales_period_idx ON sales(store_id,created_at DESC,id);
CREATE TABLE sale_items (
 store_id uuid NOT NULL, sale_id uuid NOT NULL, product_id uuid NOT NULL,
 name text NOT NULL, quantity bigint NOT NULL CHECK(quantity > 0),
 price bigint NOT NULL CHECK(price > 0), cost bigint CHECK(cost >= 0),
 total bigint NOT NULL CHECK(total > 0), PRIMARY KEY(sale_id,product_id),
 FOREIGN KEY(store_id,sale_id) REFERENCES sales(store_id,id),
 FOREIGN KEY(store_id,product_id) REFERENCES products(store_id,id)
);
CREATE TABLE returns (
 id uuid PRIMARY KEY, store_id uuid NOT NULL, sale_id uuid NOT NULL UNIQUE,
 reason text NOT NULL CHECK(length(reason) BETWEEN 1 AND 500), total bigint NOT NULL CHECK(total > 0),
 created_at timestamptz NOT NULL DEFAULT now(), FOREIGN KEY(store_id,sale_id) REFERENCES sales(store_id,id)
);
CREATE TABLE payments (
 id uuid PRIMARY KEY, store_id uuid NOT NULL, sale_id uuid NOT NULL,
 amount bigint NOT NULL CHECK(amount <> 0), method text NOT NULL CHECK(method IN ('cash','card')),
 kind text NOT NULL CHECK(kind IN ('sale','repayment','refund')),
 created_at timestamptz NOT NULL DEFAULT now(), FOREIGN KEY(store_id,sale_id) REFERENCES sales(store_id,id),
 CHECK((kind='refund' AND amount<0) OR (kind<>'refund' AND amount>0))
);
CREATE INDEX payments_sale_idx ON payments(store_id,sale_id);
CREATE INDEX payments_period_idx ON payments(store_id,created_at);
CREATE TABLE debt_entries (
 id uuid PRIMARY KEY, store_id uuid NOT NULL, customer_id uuid NOT NULL, sale_id uuid NOT NULL,
 amount bigint NOT NULL CHECK(amount <> 0), kind text NOT NULL CHECK(kind IN ('sale','repayment','return')),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(store_id,customer_id) REFERENCES customers(store_id,id),
 FOREIGN KEY(store_id,sale_id) REFERENCES sales(store_id,id)
);
CREATE INDEX debt_customer_idx ON debt_entries(store_id,customer_id,created_at);
CREATE TABLE inventory_movements (
 id uuid PRIMARY KEY, store_id uuid NOT NULL, product_id uuid NOT NULL,
 quantity bigint NOT NULL CHECK(quantity <> 0), reason text NOT NULL,
 sale_id uuid, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(store_id,product_id) REFERENCES products(store_id,id),
 FOREIGN KEY(store_id,sale_id) REFERENCES sales(store_id,id)
);
CREATE INDEX inventory_product_idx ON inventory_movements(store_id,product_id,created_at);
CREATE TABLE expenses (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id), amount bigint NOT NULL CHECK(amount>0),
 category text NOT NULL CHECK(category IN ('rent','salary','delivery','utilities','other')),
 description text NOT NULL DEFAULT '', method text NOT NULL CHECK(method IN ('cash','card')),
 occurred_on date NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE sync_operations (
 store_id uuid NOT NULL REFERENCES stores(id), command_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES users(id), request_hash text NOT NULL, response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(store_id,command_id)
);
CREATE TABLE audit_logs (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id),
 actor_id uuid NOT NULL REFERENCES users(id), action text NOT NULL, entity_id uuid NOT NULL,
 command_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
-- Financial ledgers are append-only even when accessed with the application DB role.
-- +goose StatementBegin
CREATE FUNCTION reject_ledger_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'financial ledger is append-only'; END;
$$;
-- +goose StatementEnd
CREATE TRIGGER sales_immutable BEFORE UPDATE OR DELETE ON sales FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER items_immutable BEFORE UPDATE OR DELETE ON sale_items FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER payments_immutable BEFORE UPDATE OR DELETE ON payments FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER debts_immutable BEFORE UPDATE OR DELETE ON debt_entries FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER returns_immutable BEFORE UPDATE OR DELETE ON returns FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER movements_immutable BEFORE UPDATE OR DELETE ON inventory_movements FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER expenses_immutable BEFORE UPDATE OR DELETE ON expenses FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON audit_logs FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
-- +goose Down
DROP TABLE audit_logs,sync_operations,expenses,inventory_movements,debt_entries,payments,returns,sale_items,sales,customers,products,store_members,stores,sessions,users;
DROP FUNCTION reject_ledger_mutation();
