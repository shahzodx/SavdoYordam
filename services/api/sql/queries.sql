-- name: SessionUser :one
SELECT user_id::text FROM sessions WHERE token_hash = $1 AND expires_at > now();

-- name: GetProduct :one
SELECT name, unit, price, cost, stock FROM products WHERE store_id = $1 AND id = $2;
