-- +goose Up
CREATE TABLE push_devices (
 store_id uuid NOT NULL REFERENCES stores(id), actor_id uuid NOT NULL REFERENCES users(id),
 device_id uuid NOT NULL, token text NOT NULL, language text NOT NULL CHECK(language IN ('uz','ru')),
 last_sent_at timestamptz, updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(store_id,actor_id,device_id)
);
-- +goose Down
DROP TABLE push_devices;
