-- +goose Up
ALTER TABLE sale_items ADD COLUMN discount bigint NOT NULL DEFAULT 0 CHECK(discount>=0);
ALTER TABLE returns DROP CONSTRAINT returns_sale_id_key;
CREATE TABLE return_items (
 store_id uuid NOT NULL, return_id uuid NOT NULL REFERENCES returns(id),
 sale_id uuid NOT NULL, product_id uuid NOT NULL, quantity bigint NOT NULL CHECK(quantity>0),
 total bigint NOT NULL CHECK(total>0), cost_total bigint CHECK(cost_total>=0),
 PRIMARY KEY(return_id,product_id),
 FOREIGN KEY(store_id,sale_id) REFERENCES sales(store_id,id),
 FOREIGN KEY(store_id,product_id) REFERENCES products(store_id,id)
);
INSERT INTO return_items(store_id,return_id,sale_id,product_id,quantity,total,cost_total)
 SELECT i.store_id,r.id,i.sale_id,i.product_id,i.quantity,i.total,round(i.cost::numeric*i.quantity/1000)::bigint
 FROM returns r JOIN sale_items i ON i.store_id=r.store_id AND i.sale_id=r.sale_id;
CREATE INDEX return_items_sale_idx ON return_items(store_id,sale_id,product_id);
CREATE TRIGGER return_items_immutable BEFORE UPDATE OR DELETE ON return_items FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
CREATE TABLE expense_voids (
 id uuid PRIMARY KEY, store_id uuid NOT NULL REFERENCES stores(id), expense_id uuid NOT NULL UNIQUE REFERENCES expenses(id),
 amount bigint NOT NULL CHECK(amount>0), reason text NOT NULL, occurred_on date NOT NULL,
 actor_id uuid NOT NULL REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER expense_voids_immutable BEFORE UPDATE OR DELETE ON expense_voids FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
-- +goose Down
-- Down cannot safely collapse multiple partial returns into the previous unique schema.
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Migration contains financial history; use a verified backup instead of destructive downgrade'; END $$;
-- +goose StatementEnd
