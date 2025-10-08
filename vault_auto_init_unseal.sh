#!/usr/bin/env bash
set -euo pipefail

# This script initializes and/or unseals Vault non-interactively.
# It writes unseal key shares and the initial root token to files with 0600 perms.
# Intended for bootstrapping; secure and rotate credentials afterward.

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (e.g., sudo bash $0)"; exit 1
fi

umask 077

########################################
# Configurable settings (edit as needed)
########################################
# Number of unseal key shares to generate on init
KEY_SHARES=${KEY_SHARES:-5}
# Number of shares required to unseal
KEY_THRESHOLD=${KEY_THRESHOLD:-3}
# Automatically unseal after init using the first KEY_THRESHOLD shares
AUTO_UNSEAL=${AUTO_UNSEAL:-true}
# Optional: path to a file containing previously saved unseal keys
# Accepts either the JSON file produced by this script or a TXT file
# with lines like: "Unseal Key 1: <key>"
UNSEAL_KEYS_FILE=${UNSEAL_KEYS_FILE:-}
# Where to store output files
OUTPUT_DIR=${OUTPUT_DIR:-/root/vault-boot}
# Basename used for output files; timestamp by default
OUTPUT_BASENAME=${OUTPUT_BASENAME:-vault_init_$(date +%Y%m%d_%H%M%S)}
# How long (seconds) to wait for Vault HTTP to respond
WAIT_TIMEOUT=${WAIT_TIMEOUT:-60}
# Probe interval when waiting for HTTP reachability
WAIT_INTERVAL=${WAIT_INTERVAL:-1}
# If jq is missing, auto-install via apt (yes|no|auto)
JQ_INSTALL=${JQ_INSTALL:-auto}

########################################
# Environment
########################################
if [ -z "${VAULT_ADDR:-}" ] && [ -f /etc/profile.d/vault.sh ]; then
  # shellcheck source=/dev/null
  . /etc/profile.d/vault.sh || true
fi
: "${VAULT_ADDR:=http://127.0.0.1:8200}"

########################################
# Preconditions
########################################
if ! command -v vault >/dev/null 2>&1; then
  echo "vault CLI not found in PATH. Please install Vault first."; exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  if [ "$JQ_INSTALL" = "yes" ] || { [ "$JQ_INSTALL" = "auto" ] && command -v apt-get >/dev/null 2>&1; }; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y jq
  else
    echo "jq is required but not installed. Set JQ_INSTALL=yes or install jq manually."; exit 1
  fi
fi

mkdir -p "$OUTPUT_DIR"
chmod 0700 "$OUTPUT_DIR"

########################################
# Wait for Vault HTTP
########################################
deadline=$((SECONDS + WAIT_TIMEOUT))
while true; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$VAULT_ADDR/v1/sys/health" || true)
  # Any HTTP code means the endpoint is reachable (501=uninitialized, 503=sealed, 200=active, 429=standby)
  if [ "$code" != "000" ] && [ -n "$code" ]; then
    break
  fi
  if [ $SECONDS -ge $deadline ]; then
    echo "Vault at $VAULT_ADDR not reachable within ${WAIT_TIMEOUT}s"; exit 1
  fi
  sleep "$WAIT_INTERVAL"
done

########################################
# Inspect current status
########################################
status_json=$(vault status -format=json || true)
if [ -z "$status_json" ]; then echo "Failed to read vault status"; exit 1; fi
initialized=$(echo "$status_json" | jq -r '.initialized')
sealed=$(echo "$status_json" | jq -r '.sealed')

########################################
# Initialize if needed
########################################
if [ "$initialized" = "false" ]; then
  echo "Initializing Vault (shares=$KEY_SHARES threshold=$KEY_THRESHOLD)..."
  init_json=$(vault operator init -key-shares="$KEY_SHARES" -key-threshold="$KEY_THRESHOLD" -format=json)

  json_path="$OUTPUT_DIR/$OUTPUT_BASENAME.json"
  txt_path="$OUTPUT_DIR/$OUTPUT_BASENAME.txt"

  echo "$init_json" > "$json_path"
  chmod 0600 "$json_path"

  root_token=$(echo "$init_json" | jq -r '.root_token')
  mapfile -t unseal_keys < <(echo "$init_json" | jq -r '.unseal_keys_b64[]')

  {
    echo "Vault Initialization - $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "VAULT_ADDR=$VAULT_ADDR"
    echo "key_shares=$KEY_SHARES key_threshold=$KEY_THRESHOLD"
    echo
    echo "UNSEAL KEYS (base64):"
    idx=1
    for k in "${unseal_keys[@]}"; do
      printf 'Unseal Key %d: %s\n' "$idx" "$k"
      idx=$((idx+1))
    done
    echo
    echo "Initial Root Token: $root_token"
  } > "$txt_path"
  chmod 0600 "$txt_path"

  echo "Initialization complete. Secrets saved to:"
  echo "  $txt_path"
  echo "  $json_path"

  if [ "$AUTO_UNSEAL" = "true" ]; then
    echo "Auto-unsealing with $KEY_THRESHOLD shares..."
    for i in $(seq 1 "$KEY_THRESHOLD"); do
      vault operator unseal "${unseal_keys[$((i-1))]}"
    done
  else
    echo "AUTO_UNSEAL=false; skipping unseal. Use: vault operator unseal"
  fi

  vault status | cat
  exit 0
fi

########################################
# If initialized and sealed, unseal using provided keys file
########################################
if [ "$initialized" = "true" ] && [ "$sealed" = "true" ]; then
  if [ -z "$UNSEAL_KEYS_FILE" ] || [ ! -f "$UNSEAL_KEYS_FILE" ]; then
    echo "Vault is initialized and sealed, but UNSEAL_KEYS_FILE is not set or missing."
    echo "Provide UNSEAL_KEYS_FILE pointing to the JSON/TXT created at init."
    exit 1
  fi

  echo "Unsealing Vault using keys from: $UNSEAL_KEYS_FILE"
  if jq -e . >/dev/null 2>&1 < "$UNSEAL_KEYS_FILE"; then
    mapfile -t keys < <(jq -r '.unseal_keys_b64[]' "$UNSEAL_KEYS_FILE")
  else
    mapfile -t keys < <(grep -E '^Unseal Key [0-9]+:' "$UNSEAL_KEYS_FILE" | awk -F': ' '{print $2}')
  fi

  if [ ${#keys[@]} -eq 0 ]; then
    echo "No unseal keys found in $UNSEAL_KEYS_FILE"; exit 1
  fi

  count=0
  for k in "${keys[@]}"; do
    [ -z "$k" ] && continue
    vault operator unseal "$k"
    count=$((count+1))
    sealed_now=$(vault status -format=json | jq -r '.sealed')
    if [ "$sealed_now" = "false" ]; then
      break
    fi
  done

  echo "Applied $count unseal shares. Current status:"
  vault status | cat
  exit 0
fi

########################################
# Already initialized and unsealed
########################################
echo "Vault is already initialized and unsealed. Nothing to do."
vault status | cat
exit 0


