#!/usr/bin/env bash
set -euo pipefail
: "${RESTORE_DATABASE_URL:?Set an EMPTY recovery database, never production}"
: "${AGE_IDENTITY:?Set age identity file path}"
source_file="${1:?Backup path required}"
(cd "$(dirname "$source_file")" && sha256sum -c "$(basename "$source_file").sha256")
age -d -i "$AGE_IDENTITY" "$source_file" | pg_restore --dbname="$RESTORE_DATABASE_URL" --no-owner --no-acl --single-transaction --exit-on-error
