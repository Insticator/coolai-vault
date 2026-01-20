#!/bin/bash
# Vault Restore from MinIO Script
# Restores Vault from a Raft snapshot stored in MinIO

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
RESTORE_DIR="/tmp/vault-restore"

export VAULT_ADDR

# Validate required variables
if [ -z "$MINIO_ENDPOINT" ] || [ -z "$MINIO_ACCESS_KEY" ] || [ -z "$MINIO_SECRET_KEY" ]; then
    echo "ERROR: MinIO credentials not configured in .env"
    exit 1
fi

# Configure MinIO client
mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --insecure 2>/dev/null

mkdir -p "$RESTORE_DIR"

echo "=== Vault Restore from MinIO ==="
echo ""

# List available backups
echo "Available backups:"
echo "------------------"
mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" --insecure | grep -E '\.snap$' | sort -r | head -10
echo ""

# Get snapshot name
if [ -z "$1" ]; then
    SNAPSHOT_NAME=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" --insecure | grep -E '\.snap$' | sort -r | head -1 | awk '{print $NF}')
    if [ -z "$SNAPSHOT_NAME" ]; then
        echo "ERROR: No snapshots found in MinIO"
        exit 1
    fi
    echo "Using latest snapshot: $SNAPSHOT_NAME"
else
    SNAPSHOT_NAME="$1"
    echo "Using specified snapshot: $SNAPSHOT_NAME"
fi

# Download snapshot
SNAPSHOT_FILE="$RESTORE_DIR/$SNAPSHOT_NAME"
echo ""
echo "Downloading snapshot from MinIO..."
mc cp "$MINIO_ALIAS/$MINIO_BUCKET/$SNAPSHOT_NAME" "$SNAPSHOT_FILE" --insecure

# Download init keys if available
mc cp "$MINIO_ALIAS/$MINIO_BUCKET/vault_init*.json" "$RESTORE_DIR/" --insecure 2>/dev/null || true

# Check Vault status and unseal if needed
echo ""
echo "Checking Vault status..."
SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.sealed')

if [ "$SEAL_STATUS" = "true" ]; then
    echo "Vault is sealed. Attempting to unseal..."
    
    INIT_FILE=$(ls -t "$RESTORE_DIR"/vault_init*.json "$SCRIPT_DIR/../vault-boot/vault_init.json" 2>/dev/null | head -1)
    if [ -f "$INIT_FILE" ]; then
        for i in 0 1 2; do
            KEY=$(jq -r ".unseal_keys_b64[$i]" "$INIT_FILE")
            vault operator unseal "$KEY" > /dev/null
        done
        export VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
        echo "Vault unsealed."
    else
        echo "ERROR: Could not find unseal keys"
        exit 1
    fi
fi

# Set token if not already set
if [ -z "$VAULT_TOKEN" ]; then
    INIT_FILE=$(ls -t "$RESTORE_DIR"/vault_init*.json "$SCRIPT_DIR/../vault-boot/vault_init.json" 2>/dev/null | head -1)
    if [ -f "$INIT_FILE" ]; then
        export VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
    fi
fi

# Restore from snapshot
echo ""
echo "Restoring Vault from snapshot..."
vault operator raft snapshot restore -force "$SNAPSHOT_FILE"

echo ""
echo "=== Restore Complete ==="
echo ""
echo "NOTE: Restart Vault and unseal with original keys:"
echo "  systemctl restart vault"
echo "  ./init_unseal.sh"

# Cleanup
rm -rf "$RESTORE_DIR"
