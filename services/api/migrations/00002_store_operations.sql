-- +goose Up
ALTER TABLE stores ADD COLUMN retail_type text NOT NULL DEFAULT 'general';
ALTER TABLE products ADD COLUMN category text NOT NULL DEFAULT '';
ALTER TABLE products ADD COLUMN archived boolean NOT NULL DEFAULT false;
CREATE INDEX products_active_idx ON products(store_id,archived,category,lower(name));
CREATE TABLE staff_invitations (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id), email text NOT NULL,
 token_hash text NOT NULL UNIQUE, expires_at timestamptz NOT NULL,
 created_by uuid NOT NULL REFERENCES users(id), accepted_by uuid REFERENCES users(id),
 revoked boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX staff_invites_store_idx ON staff_invitations(store_id,created_at);
CREATE TABLE purchases (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id), supplier text NOT NULL DEFAULT '',
 note text NOT NULL DEFAULT '', total bigint NOT NULL CHECK(total>0),
 created_by uuid NOT NULL REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(store_id,id)
);
CREATE TABLE purchase_items (
 store_id uuid NOT NULL, purchase_id uuid NOT NULL, product_id uuid NOT NULL,
 name text NOT NULL, quantity bigint NOT NULL CHECK(quantity>0),
 unit_cost bigint NOT NULL CHECK(unit_cost>0), total bigint NOT NULL CHECK(total>0),
 PRIMARY KEY(purchase_id,product_id),
 FOREIGN KEY(store_id,purchase_id) REFERENCES purchases(store_id,id),
 FOREIGN KEY(store_id,product_id) REFERENCES products(store_id,id)
);
CREATE TRIGGER purchases_immutable BEFORE UPDATE OR DELETE ON purchases FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TRIGGER purchase_items_immutable BEFORE UPDATE OR DELETE ON purchase_items FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TABLE offline_leases (
 store_id uuid PRIMARY KEY REFERENCES stores(id), id uuid NOT NULL UNIQUE,
 device_id uuid NOT NULL, actor_id uuid NOT NULL REFERENCES users(id),
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
-- +goose Down
DROP TABLE offline_leases,purchase_items,purchases,staff_invitations;
DROP INDEX products_active_idx;
ALTER TABLE products DROP COLUMN archived, DROP COLUMN category;
ALTER TABLE stores DROP COLUMN retail_type;
