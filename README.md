# CoolAI Vault

HashiCorp Vault deployment and management scripts for CoolAI infrastructure.

## Overview

This repository contains scripts for deploying, managing, and backing up HashiCorp Vault with:
- Raft integrated storage
- MinIO (S3-compatible) backup integration
- Automatic log rotation and cleanup
- Scheduled backup automation

## Prerequisites

- Ubuntu/Debian Linux server
- Root access
- MinIO or S3-compatible storage for backups
- `curl`, `jq` installed (scripts will install if missing)

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/Insticator/coolai-vault.git
cd coolai-vault

# Copy and edit environment file
cp .env.example .env
nano .env  # Fill in your values
```

### 2. Install Vault

```bash
sudo ./scripts/install_vault.sh
```

### 3. Initialize and Unseal

```bash
./scripts/init_unseal.sh
```

This will:
- Initialize Vault with 5 key shares (3 required to unseal)
- Save unseal keys and root token to `vault-boot/`
- Automatically unseal Vault

**Important:** Back up `vault-boot/vault_init.json` securely!

### 4. Setup Automated Backups

```bash
sudo ./scripts/setup_cron.sh
```

This configures:
- Hourly Raft snapshots to MinIO
- Daily log cleanup at 3 AM
- Journal size limits (500MB max)
- Vault log rotation (7 days retention)

## Scripts

| Script | Description |
|--------|-------------|
| `install_vault.sh` | Installs and configures HashiCorp Vault |
| `init_unseal.sh` | Initializes Vault and performs unsealing |
| `backup_to_minio.sh` | Takes Raft snapshot and uploads to MinIO |
| `restore_from_minio.sh` | Restores Vault from MinIO backup |
| `cleanup_logs.sh` | Cleans old logs to prevent storage overflow |
| `setup_cron.sh` | Configures automated backups and cleanup |

## Configuration

All scripts read from `.env` file in the project root. Key settings:

```bash
# Vault
VAULT_ADDR=http://127.0.0.1:8200
VAULT_TOKEN=hvs.xxxxx

# MinIO Backup
MINIO_ENDPOINT=https://minio.example.com:9443
MINIO_ACCESS_KEY=admin
MINIO_SECRET_KEY=secretkey
MINIO_BUCKET=vault-backups
```

See `.env.example` for all available options.

## Backup & Restore

### Manual Backup

```bash
./scripts/backup_to_minio.sh
```

### Restore from Backup

```bash
# List available backups and restore latest
./scripts/restore_from_minio.sh

# Restore specific snapshot
./scripts/restore_from_minio.sh vault_raft_snapshot_20260120_120000.snap
```

### After Restore

```bash
# Restart Vault
sudo systemctl restart vault

# Unseal with original keys
./scripts/init_unseal.sh
```

## Disaster Recovery

### Complete Server Recovery

1. **Deploy new server** with Ubuntu/Debian

2. **Clone repository and configure:**
   ```bash
   git clone https://github.com/Insticator/coolai-vault.git
   cd coolai-vault
   cp .env.example .env
   # Edit .env with MinIO credentials
   ```

3. **Install Vault:**
   ```bash
   sudo ./scripts/install_vault.sh
   ```

4. **Download and restore backup:**
   ```bash
   # Install MinIO client
   curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
   chmod +x /usr/local/bin/mc
   
   # Restore from MinIO
   ./scripts/restore_from_minio.sh
   ```

5. **Restart and unseal:**
   ```bash
   sudo systemctl restart vault
   ./scripts/init_unseal.sh
   ```

## Directory Structure

```
coolai-vault/
├── .env.example        # Environment template
├── .env                # Your configuration (git-ignored)
├── .gitignore
├── README.md
├── scripts/
│   ├── install_vault.sh
│   ├── init_unseal.sh
│   ├── backup_to_minio.sh
│   ├── restore_from_minio.sh
│   ├── cleanup_logs.sh
│   └── setup_cron.sh
└── vault-boot/         # Unseal keys (git-ignored)
    └── vault_init.json
```

## Security Notes

- **Never commit `.env` or `vault-boot/`** - they contain sensitive credentials
- Store unseal keys in multiple secure locations
- Enable TLS in production (modify `vault.hcl`)
- Restrict network access to Vault port (8200)
- Regularly rotate root token and create limited-access tokens

## Log Management

The setup includes automatic log management to prevent storage issues:

- **Vault logs:** Rotated daily, 7 days retention, compressed
- **System journal:** Limited to 500MB, 2 weeks retention
- **Cleanup script:** Runs daily, removes old logs and temp files

## Troubleshooting

### Vault is Sealed

```bash
./scripts/init_unseal.sh
```

### Cannot Connect to Vault

```bash
# Check service status
sudo systemctl status vault

# Check logs
sudo journalctl -u vault -f
```

### Storage Full

```bash
# Run cleanup manually
sudo ./scripts/cleanup_logs.sh

# Check disk usage
df -h /
```

### Restore Failed

Ensure you have the original unseal keys. The restore process requires:
1. Vault to be running (even if sealed)
2. Valid root token or unseal keys
3. Network access to MinIO

## License

MIT License - See LICENSE file for details.
