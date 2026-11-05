#!/usr/bin/env bash
# Operates only on a disposable PostgreSQL cluster. Leaves the recovered DB for inspection.
set -euo pipefail
: "${TEST_DATABASE_URL:?Set a disposable test database URL}"
: "${RESTORE_DATABASE_URL:?Set a separate empty disposable database URL}"
test_dir="$(mktemp -d)"
chmod 700 "$test_dir"
age-keygen -o "$test_dir/identity.txt"
backup_recipient="$(age-keygen -y "$test_dir/identity.txt")"
DATABASE_URL="$TEST_DATABASE_URL" BACKUP_RECIPIENT="$backup_recipient" bash infra/backup.sh "$test_dir/backup.dump.age"
AGE_IDENTITY="$test_dir/identity.txt" bash infra/restore.sh "$test_dir/backup.dump.age"
query="SELECT 'sales',count(*) FROM sales UNION ALL SELECT 'sale_items',count(*) FROM sale_items UNION ALL SELECT 'returns',count(*) FROM returns UNION ALL SELECT 'return_items',count(*) FROM return_items UNION ALL SELECT 'payments',count(*) FROM payments UNION ALL SELECT 'debt_entries',count(*) FROM debt_entries UNION ALL SELECT 'inventory_movements',count(*) FROM inventory_movements UNION ALL SELECT 'expenses',count(*) FROM expenses UNION ALL SELECT 'expense_voids',count(*) FROM expense_voids UNION ALL SELECT 'purchases',count(*) FROM purchases UNION ALL SELECT 'purchase_items',count(*) FROM purchase_items UNION ALL SELECT 'audit_logs',count(*) FROM audit_logs ORDER BY 1"
psql "$TEST_DATABASE_URL" -Atc "$query" > "$test_dir/source.txt"
psql "$RESTORE_DATABASE_URL" -Atc "$query" > "$test_dir/restored.txt"
diff -u "$test_dir/source.txt" "$test_dir/restored.txt"
psql "$RESTORE_DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM products p WHERE stock <> coalesce((SELECT sum(m.quantity) FROM inventory_movements m WHERE m.store_id=p.store_id AND m.product_id=p.id),0)) THEN
  RAISE EXCEPTION 'stock ledger mismatch';
 END IF;
 IF EXISTS(SELECT 1 FROM customers c WHERE coalesce((SELECT sum(d.amount) FROM debt_entries d WHERE d.store_id=c.store_id AND d.customer_id=c.id),0)<0) THEN
  RAISE EXCEPTION 'negative customer debt';
 END IF;
 IF EXISTS(SELECT 1 FROM sale_items i WHERE coalesce((SELECT sum(r.quantity) FROM return_items r WHERE r.store_id=i.store_id AND r.sale_id=i.sale_id AND r.product_id=i.product_id),0)>i.quantity) THEN
  RAISE EXCEPTION 'returned quantity exceeds sold quantity';
 END IF;
 IF EXISTS(SELECT 1 FROM returns r WHERE r.total<>coalesce((SELECT sum(i.total) FROM return_items i WHERE i.return_id=r.id),0)) THEN
  RAISE EXCEPTION 'return total mismatch';
 END IF;
 IF EXISTS(SELECT 1 FROM purchases p WHERE p.total<>coalesce((SELECT sum(i.total) FROM purchase_items i WHERE i.purchase_id=p.id),0)) THEN
  RAISE EXCEPTION 'purchase total mismatch';
 END IF;
END $$;
SQL
printf 'Encrypted backup and restore verified. Test artifacts: %s\n' "$test_dir"
