#!/bin/bash
# Vault Backup to MinIO Script
# Backs up Vault Raft snapshots to MinIO (S3-compatible storage)

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Configuration from .env
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-}"
MINIO_BUCKET="${MINIO_BUCKET:-vault-backups}"
MINIO_ALIAS="${MINIO_ALIAS:-coolai}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/vault-backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

export VAULT_ADDR
export VAULT_TOKEN

# Validate required variables
if [ -z "$MINIO_ENDPOINT" ] || [ -z "$MINIO_ACCESS_KEY" ] || [ -z "$MINIO_SECRET_KEY" ]; then
    echo "ERROR: MinIO credentials not configured in .env"
    echo "Required: MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY"
    exit 1
fi

if [ -z "$VAULT_TOKEN" ]; then
    # Try to get token from vault-boot
    if [ -f "$SCRIPT_DIR/../vault-boot/vault_init.json" ]; then
        export VAULT_TOKEN=$(jq -r '.root_token' "$SCRIPT_DIR/../vault-boot/vault_init.json")
    else
        echo "ERROR: VAULT_TOKEN not set and no init file found"
        exit 1
    fi
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Vault Backup Started: $TIMESTAMP ==="

# Check if Vault is sealed
SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.sealed')
if [ "$SEAL_STATUS" = "true" ]; then
    echo "ERROR: Vault is sealed. Please unseal first."
    exit 1
fi

# Configure MinIO client
mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --insecure 2>/dev/null

# Create bucket if not exists
mc mb "$MINIO_ALIAS/$MINIO_BUCKET" --insecure 2>/dev/null || true

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Take Raft snapshot
SNAPSHOT_FILE="$BACKUP_DIR/vault_raft_snapshot_$TIMESTAMP.snap"
echo "Taking Raft snapshot..."
vault operator raft snapshot save "$SNAPSHOT_FILE"
echo "Snapshot saved: $SNAPSHOT_FILE"

# Upload to MinIO
echo "Uploading to MinIO..."
mc cp "$SNAPSHOT_FILE" "$MINIO_ALIAS/$MINIO_BUCKET/" --insecure

# Cleanup old local backups (keep last 5)
echo "Cleaning up old local backups..."
ls -t "$BACKUP_DIR"/vault_raft_snapshot_*.snap 2>/dev/null | tail -n +6 | xargs -r rm -f

# Cleanup old MinIO backups
echo "Cleaning up MinIO backups older than $RETENTION_DAYS days..."
mc rm "$MINIO_ALIAS/$MINIO_BUCKET/" --insecure --older-than "${RETENTION_DAYS}d" --recursive --force 2>/dev/null || true

echo ""
echo "=== Backup Complete ==="
echo "Local: $SNAPSHOT_FILE"
echo "MinIO: $MINIO_ALIAS/$MINIO_BUCKET/$(basename $SNAPSHOT_FILE)"
