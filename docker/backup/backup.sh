#!/usr/bin/env bash
# T021 — Daily encrypted backup: MariaDB dump (AES-256) + doc_data volume sync
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../docker/.env" 2>/dev/null || true

BACKUP_DIR="${BACKUP_DIR:-/opt/med_pront/backups}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
DB_HOST="${MYSQL_HOST:-db}"
DB_NAME="${MYSQL_DATABASE:-openemr}"
DB_USER="${MYSQL_USER:-openemr}"
DB_PASS="${MYSQL_PASSWORD:-}"
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
TEST_MODE=false

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

for arg in "$@"; do
  [[ "$arg" == "--test" ]] && TEST_MODE=true
done

[[ -z "$ENCRYPTION_KEY" ]] && die "BACKUP_ENCRYPTION_KEY not set in environment."
mkdir -p "$BACKUP_DIR"

DB_DUMP="${BACKUP_DIR}/db_${TIMESTAMP}.sql.gz"
DB_ENC="${BACKUP_DIR}/db_${TIMESTAMP}.sql.gz.enc"

log "=== Med_Pront Backup — $TIMESTAMP ==="

log "Step 1: MariaDB dump"
if $TEST_MODE; then
  log "[TEST] Skipping real mysqldump — creating empty test file."
  echo "-- test backup $(date)" | gzip > "$DB_DUMP"
else
  docker exec med_pront-db-1 mysqldump \
    -u "$DB_USER" -p"$DB_PASS" \
    --single-transaction \
    --routines \
    --triggers \
    --hex-blob \
    "$DB_NAME" 2>/dev/null | gzip > "$DB_DUMP" \
    || die "mysqldump failed"
fi
log "Dump created: $DB_DUMP ($(du -sh "$DB_DUMP" | cut -f1))"

log "Step 2: Encrypt with AES-256-CBC"
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
  -in "$DB_DUMP" \
  -out "$DB_ENC" \
  -pass pass:"$ENCRYPTION_KEY"
rm -f "$DB_DUMP"
log "Encrypted: $DB_ENC"

log "Step 3: Document volume snapshot"
DOC_SNAP="${BACKUP_DIR}/docs_${TIMESTAMP}.tar.gz.enc"
if $TEST_MODE; then
  log "[TEST] Skipping volume snapshot."
else
  docker run --rm \
    -v med_pront_doc_data:/data:ro \
    -v "$BACKUP_DIR":/backup \
    alpine sh -c "tar czf - /data 2>/dev/null" \
    | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
      -out "$DOC_SNAP" \
      -pass pass:"$ENCRYPTION_KEY"
  log "Docs snapshot: $DOC_SNAP ($(du -sh "$DOC_SNAP" | cut -f1))"
fi

log "Step 4: Verify encrypted files"
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -d \
  -in "$DB_ENC" -pass pass:"$ENCRYPTION_KEY" 2>/dev/null | gunzip -t \
  && log "DB backup integrity: OK" \
  || die "DB backup integrity check FAILED"

log "Step 5: Cleanup old backups (>${RETENTION_DAYS} days)"
find "$BACKUP_DIR" -name "*.enc" -mtime +"$RETENTION_DAYS" -delete
log "Old backups removed."

if [[ -n "$S3_BUCKET" ]] && ! $TEST_MODE; then
  log "Step 6: Upload to S3-compatible storage"
  if command -v aws &>/dev/null; then
    aws s3 cp "$DB_ENC" "s3://${S3_BUCKET}/db/" --sse AES256
    [[ -f "$DOC_SNAP" ]] && aws s3 cp "$DOC_SNAP" "s3://${S3_BUCKET}/docs/" --sse AES256
    log "Upload complete."
  else
    log "WARNING: aws CLI not found, skipping upload."
  fi
fi

log "=== Backup complete ==="
ls -lh "$BACKUP_DIR"/*.enc 2>/dev/null | tail -5 || true
