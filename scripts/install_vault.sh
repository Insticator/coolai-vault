#!/bin/bash
# HashiCorp Vault Installation Script
# Installs and configures Vault with Raft storage on Debian/Ubuntu

set -e

# Load environment variables if .env exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Configuration (can be overridden by .env)
VAULT_VERSION="${VAULT_VERSION:-1.20.4}"
VAULT_DATA_DIR="${VAULT_DATA_DIR:-/var/lib/vault}"
VAULT_CONFIG_DIR="${VAULT_CONFIG_DIR:-/etc/vault.d}"
VAULT_LOG_DIR="${VAULT_LOG_DIR:-/var/log/vault}"
VAULT_TLS_DIR="${VAULT_TLS_DIR:-/opt/vault/tls}"
VAULT_PORT="${VAULT_PORT:-8200}"
VAULT_CLUSTER_PORT="${VAULT_CLUSTER_PORT:-8201}"
VAULT_NODE_ID="${VAULT_NODE_ID:-vault-node-1}"

# Get server IP
SERVER_IP="${VAULT_API_ADDR:-$(hostname -I | awk '{print $1}')}"

echo "=== HashiCorp Vault Installation ==="
echo "Version: $VAULT_VERSION"
echo "Server IP: $SERVER_IP"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root"
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq curl gnupg lsb-release jq

# Add HashiCorp GPG key and repository
echo "Adding HashiCorp repository..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null || true
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list

# Install Vault
echo "Installing Vault..."
apt-get update -qq
apt-get install -y -qq vault

# Create vault user if not exists
if ! id -u vault &>/dev/null; then
    useradd --system --home /etc/vault.d --shell /bin/false vault
fi

# Create directories
echo "Creating directories..."
mkdir -p "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR" "$VAULT_LOG_DIR" "$VAULT_TLS_DIR"
chown -R vault:vault "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR" "$VAULT_LOG_DIR" "$VAULT_TLS_DIR"
chmod 750 "$VAULT_DATA_DIR" "$VAULT_LOG_DIR"
chmod 700 "$VAULT_TLS_DIR"

# Create Vault configuration
echo "Creating Vault configuration..."
cat > "$VAULT_CONFIG_DIR/vault.hcl" << EOF
# Vault Configuration

ui = true
disable_mlock = false
log_level = "info"

storage "raft" {
  path    = "$VAULT_DATA_DIR"
  node_id = "$VAULT_NODE_ID"
}

listener "tcp" {
  address         = "0.0.0.0:$VAULT_PORT"
  cluster_address = "0.0.0.0:$VAULT_CLUSTER_PORT"
  tls_disable     = 1
}

api_addr     = "http://$SERVER_IP:$VAULT_PORT"
cluster_addr = "http://$SERVER_IP:$VAULT_CLUSTER_PORT"
EOF

chown vault:vault "$VAULT_CONFIG_DIR/vault.hcl"
chmod 640 "$VAULT_CONFIG_DIR/vault.hcl"

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/vault.service << 'EOF'
[Unit]
Description=HashiCorp Vault - A tool for managing secrets
Documentation=https://developer.hashicorp.com/vault/docs
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity
LockPersonality=yes
MemoryDenyWriteExecute=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes

[Install]
WantedBy=multi-user.target
EOF

# Create environment profile
cat > /etc/profile.d/vault.sh << EOF
export VAULT_ADDR="http://$SERVER_IP:$VAULT_PORT"
EOF

# Reload and start Vault
echo "Starting Vault service..."
systemctl daemon-reload
systemctl enable vault
systemctl start vault

# Wait for Vault to be ready
echo "Waiting for Vault to start..."
sleep 5

echo ""
echo "=== Installation Complete ==="
echo "Vault Address: http://$SERVER_IP:$VAULT_PORT"
echo ""
echo "Next steps:"
echo "1. Initialize Vault: vault operator init"
echo "2. Unseal Vault with 3 of 5 unseal keys"
echo "3. Login with root token"
echo ""
echo "Or run: ./init_unseal.sh"
