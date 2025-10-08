#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (e.g., sudo bash $0)"; exit 1
fi

umask 027

# Flags
REINSTALL=false
PURGE_DATA=false
while [ $# -gt 0 ]; do
  case "$1" in
    --reinstall)
      REINSTALL=true
      shift
      ;;
    --purge-data)
      PURGE_DATA=true
      shift
      ;;
    -h|--help)
      echo "Usage: sudo bash $0 [--reinstall] [--purge-data]"
      echo "  --reinstall   Remove existing Vault package and reinstall (preserves data by default)"
      echo "  --purge-data  With --reinstall, also delete /var/lib/vault and /etc/vault.d"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"; exit 1
      ;;
  esac
done

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script currently supports Debian/Ubuntu (apt). Ask for an RHEL/others variant if needed."
  exit 1
fi

. /etc/os-release

VAULT_INSTALLED=false
if dpkg -s vault >/dev/null 2>&1 || command -v vault >/dev/null 2>&1; then
  VAULT_INSTALLED=true
fi

DO_INSTALL=false
if [ "$REINSTALL" = true ] && [ "$VAULT_INSTALLED" = true ]; then
  echo "Reinstall requested; stopping and removing existing Vault package..."
  systemctl stop vault 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get remove -y vault || true
  if [ "$PURGE_DATA" = true ]; then
    echo "Purging Vault data and config..."
    rm -rf /var/lib/vault /etc/vault.d /var/log/vault || true
    rm -f /etc/systemd/system/vault.service || true
  fi
  DO_INSTALL=true
elif [ "$VAULT_INSTALLED" = false ]; then
  DO_INSTALL=true
fi

if [ "$DO_INSTALL" = true ]; then
  apt-get update -y
  apt-get install -y curl gpg coreutils

  install -m 0755 -d /usr/share/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor --batch --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  chmod 0644 /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${VERSION_CODENAME} main" \
    > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y vault
else
  echo "Vault already installed; skipping package installation. Use --reinstall to force reinstall."
fi

# Ensure vault user exists (package usually creates it; this is safe if it already exists)
if ! id -u vault >/dev/null 2>&1; then
  useradd --system --home /etc/vault.d --shell /usr/sbin/nologin vault
fi

install -d -o vault -g vault -m 0750 /etc/vault.d /var/lib/vault /var/log/vault

# Determine primary IPv4 for api_addr/cluster_addr
IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
if [ -z "${IP:-}" ]; then IP="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi
: "${IP:=127.0.0.1}"

WROTE_CONFIG=false
if [ "$REINSTALL" = true ] || [ ! -f /etc/vault.d/vault.hcl ]; then
  cat > /etc/vault.d/vault.hcl <<EOF
ui = true
disable_mlock = false

storage "raft" {
  path    = "/var/lib/vault"
  node_id = "vault-node-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 1
}

api_addr     = "http://$IP:8200"
cluster_addr = "http://$IP:8201"

log_level = "info"
EOF
  WROTE_CONFIG=true
else
  echo "/etc/vault.d/vault.hcl exists; not overwriting."
fi

chown -R vault:vault /etc/vault.d /var/lib/vault /var/log/vault
[ -f /etc/vault.d/vault.hcl ] && chmod 0640 /etc/vault.d/vault.hcl || true

# Hardened systemd unit (overrides distro unit)
WROTE_UNIT=false
if [ "$REINSTALL" = true ] || [ ! -f /etc/systemd/system/vault.service ]; then
  cat > /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description=HashiCorp Vault - A tool for managing secrets
Documentation=https://developer.hashicorp.com/vault/docs
After=network-online.target
Wants=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

[Service]
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitMEMLOCK=infinity
CapabilityBoundingSet=CAP_IPC_LOCK
AmbientCapabilities=CAP_IPC_LOCK
SecureBits=keep-caps
NoNewPrivileges=true

ProtectSystem=full
ProtectHome=read-only
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectKernelLogs=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
RestrictNamespaces=true

[Install]
WantedBy=multi-user.target
EOF
  WROTE_UNIT=true
else
  echo "/etc/systemd/system/vault.service exists; not overwriting."
fi

systemctl daemon-reload
systemctl enable vault
if systemctl is-active --quiet vault; then
  if [ "$REINSTALL" = true ] || [ "$WROTE_CONFIG" = true ] || [ "$WROTE_UNIT" = true ]; then
    systemctl restart vault
  fi
else
  systemctl start vault
fi
systemctl --no-pager status vault | cat || true

# Convenience env for CLI
if [ "$REINSTALL" = true ] || [ ! -f /etc/profile.d/vault.sh ]; then
  cat > /etc/profile.d/vault.sh <<EOF
export VAULT_ADDR="http://$IP:8200"
EOF
  chmod 0644 /etc/profile.d/vault.sh
fi

echo
echo "Vault installed and started."
echo "Next steps:"
echo "  1) Initialize: 'vault operator init' (store unseal keys + root token securely)"
echo "  2) Unseal: 'vault operator unseal' (repeat until Sealed: false)"
echo "  3) Restrict HTTP access via firewall/security groups to trusted sources only"
echo "  4) Plan to enable TLS (set listener.tls_* in /etc/vault.d/vault.hcl) before internet exposure"
echo "  5) Optionally: 'vault audit enable file file_path=/var/log/vault/audit.log'"