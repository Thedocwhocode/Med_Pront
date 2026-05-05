#!/usr/bin/env bash
# T022 — Restore: decrypt and recover DB + doc_data volume
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../docker/.env" 2>/dev/null || true

BACKUP_DIR="${BACKUP_DIR:-/opt/med_pront/backups}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
DB_HOST="${MYSQL_HOST:-db}"
DB_NAME="${MYSQL_DATABASE:-openemr}"
DB_USER="${MYSQL_USER:-openemr}"
DB_PASS="${MYSQL_PASSWORD:-}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 --db <db_backup.sql.gz.enc> [--docs <docs_backup.tar.gz.enc>] [--dry-run]

Options:
  --db      Path to encrypted DB backup file (required)
  --docs    Path to encrypted docs backup file (optional)
  --dry-run Decrypt and verify only, do not restore
EOF
  exit 1
}

DB_FILE=""
DOCS_FILE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)    DB_FILE="$2"; shift 2;;
    --docs)  DOCS_FILE="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    *) usage;;
  esac
done

[[ -z "$DB_FILE" ]] && usage
[[ -z "$ENCRYPTION_KEY" ]] && die "BACKUP_ENCRYPTION_KEY not set."
[[ ! -f "$DB_FILE" ]] && die "DB backup file not found: $DB_FILE"

log "=== Med_Pront Restore ==="
log "DB backup: $DB_FILE"
$DRY_RUN && log "DRY RUN — no data will be modified."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

log "Step 1: Decrypt DB backup"
DB_DECRYPTED="${TMPDIR}/restore.sql.gz"
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -d \
  -in "$DB_FILE" \
  -out "$DB_DECRYPTED" \
  -pass pass:"$ENCRYPTION_KEY" \
  || die "Decryption failed. Wrong key?"
log "Decryption OK."

log "Step 2: Verify SQL integrity"
gunzip -t "$DB_DECRYPTED" || die "SQL dump is corrupted."
log "Integrity check: OK"

if ! $DRY_RUN; then
  log "Step 3: Restore DB (will DROP and recreate $DB_NAME)"
  read -rp "This will ERASE the current database. Type 'yes' to confirm: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && die "Restore aborted."

  gunzip -c "$DB_DECRYPTED" \
    | docker exec -i med_pront-db-1 mysql \
        -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    || die "DB restore failed."
  log "DB restore complete."
fi

if [[ -n "$DOCS_FILE" ]]; then
  [[ ! -f "$DOCS_FILE" ]] && die "Docs backup file not found: $DOCS_FILE"

  log "Step 4: Decrypt docs backup"
  DOCS_DECRYPTED="${TMPDIR}/docs.tar.gz"
  openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -d \
    -in "$DOCS_FILE" \
    -out "$DOCS_DECRYPTED" \
    -pass pass:"$ENCRYPTION_KEY" \
    || die "Docs decryption failed."
  log "Docs decryption OK."

  if ! $DRY_RUN; then
    log "Step 5: Restore doc_data volume"
    docker run --rm \
      -v med_pront_doc_data:/data \
      -v "$TMPDIR":/backup \
      alpine sh -c "rm -rf /data/* && tar xzf /backup/docs.tar.gz -C / --strip-components=1"
    log "Docs restore complete."
  fi
fi

log "=== Restore complete ==="
