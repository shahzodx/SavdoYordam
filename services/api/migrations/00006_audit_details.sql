-- +goose Up
ALTER TABLE audit_logs ADD COLUMN details jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE expenses ADD CONSTRAINT expenses_store_id_id_unique UNIQUE(store_id,id);
ALTER TABLE expense_voids ADD CONSTRAINT expense_voids_tenant_fk FOREIGN KEY(store_id,expense_id) REFERENCES expenses(store_id,id);
ALTER TABLE returns ADD CONSTRAINT returns_store_id_id_unique UNIQUE(store_id,id);
ALTER TABLE return_items ADD CONSTRAINT return_items_tenant_fk FOREIGN KEY(store_id,return_id) REFERENCES returns(store_id,id);
ALTER TABLE push_devices ADD CONSTRAINT push_membership_fk FOREIGN KEY(store_id,actor_id) REFERENCES store_members(store_id,user_id) ON DELETE CASCADE;
-- +goose Down
ALTER TABLE push_devices DROP CONSTRAINT push_membership_fk;
ALTER TABLE return_items DROP CONSTRAINT return_items_tenant_fk;
ALTER TABLE returns DROP CONSTRAINT returns_store_id_id_unique;
ALTER TABLE expense_voids DROP CONSTRAINT expense_voids_tenant_fk;
ALTER TABLE expenses DROP CONSTRAINT expenses_store_id_id_unique;
ALTER TABLE audit_logs DROP COLUMN details;
