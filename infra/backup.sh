#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?Set DATABASE_URL}"
: "${BACKUP_RECIPIENT:?Set an age public recipient key}"
dest="${1:?Output .dump.age path required}"
umask 077
pg_dump --dbname="$DATABASE_URL" --format=custom --no-owner --no-acl | age -r "$BACKUP_RECIPIENT" -o "$dest"
(cd "$(dirname "$dest")" && sha256sum "$(basename "$dest")") > "$dest.sha256"
