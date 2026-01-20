#!/bin/bash
# Vault Initialization and Unsealing Script
# Initializes Vault and saves unseal keys securely

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_KEYS_DIR="${VAULT_KEYS_DIR:-$SCRIPT_DIR/../vault-boot}"
UNSEAL_SHARES="${VAULT_UNSEAL_SHARES:-5}"
UNSEAL_THRESHOLD="${VAULT_UNSEAL_THRESHOLD:-3}"

export VAULT_ADDR

echo "=== Vault Initialization ==="
echo "Vault Address: $VAULT_ADDR"
echo "Keys Directory: $VAULT_KEYS_DIR"
echo ""

# Wait for Vault to be available
echo "Waiting for Vault to be available..."
for i in {1..30}; do
    if curl -s "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Check if already initialized
INIT_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.initialized')
if [ "$INIT_STATUS" = "true" ]; then
    echo "Vault is already initialized."
    
    # Check if sealed
    SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.sealed')
    if [ "$SEAL_STATUS" = "true" ]; then
        echo "Vault is sealed. Attempting to unseal..."
        
        if [ -f "$VAULT_KEYS_DIR/vault_init.json" ]; then
            for i in 0 1 2; do
                KEY=$(jq -r ".unseal_keys_b64[$i]" "$VAULT_KEYS_DIR/vault_init.json")
                vault operator unseal "$KEY" > /dev/null
            done
            echo "Vault unsealed successfully!"
        else
            echo "ERROR: No unseal keys found at $VAULT_KEYS_DIR/vault_init.json"
            exit 1
        fi
    else
        echo "Vault is already unsealed."
    fi
    exit 0
fi

# Initialize Vault
echo "Initializing Vault..."
mkdir -p "$VAULT_KEYS_DIR"
chmod 700 "$VAULT_KEYS_DIR"

INIT_OUTPUT=$(vault operator init \
    -key-shares="$UNSEAL_SHARES" \
    -key-threshold="$UNSEAL_THRESHOLD" \
    -format=json)

# Save init output
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "$INIT_OUTPUT" > "$VAULT_KEYS_DIR/vault_init.json"
echo "$INIT_OUTPUT" > "$VAULT_KEYS_DIR/vault_init_$TIMESTAMP.json"
chmod 600 "$VAULT_KEYS_DIR"/*.json

echo "Initialization complete. Keys saved to $VAULT_KEYS_DIR/"

# Unseal Vault
echo ""
echo "Unsealing Vault..."
for i in 0 1 2; do
    KEY=$(echo "$INIT_OUTPUT" | jq -r ".unseal_keys_b64[$i]")
    vault operator unseal "$KEY" > /dev/null
done

echo "Vault unsealed successfully!"

# Extract and display root token
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
echo ""
echo "=== IMPORTANT ==="
echo "Root Token: $ROOT_TOKEN"
echo ""
echo "Unseal keys and root token saved to: $VAULT_KEYS_DIR/vault_init.json"
echo "BACKUP THESE KEYS SECURELY!"
