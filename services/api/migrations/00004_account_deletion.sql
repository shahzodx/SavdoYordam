-- +goose Up
ALTER TABLE users ADD COLUMN deleted_at timestamptz;
ALTER TABLE stores ADD COLUMN archived boolean NOT NULL DEFAULT false;
CREATE TABLE account_deletions (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 procedure text NOT NULL DEFAULT 'account-anonymized-store-archived-financial-ledger-retained'
);
-- +goose Down
DROP TABLE account_deletions;
ALTER TABLE stores DROP COLUMN archived;
ALTER TABLE users DROP COLUMN deleted_at;
