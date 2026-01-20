#!/bin/bash
# Setup Cron Jobs for Vault Maintenance
# Configures automatic backups and log cleanup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Setting Up Cron Jobs ==="

# Backup cron (hourly)
BACKUP_CRON="0 * * * * $SCRIPT_DIR/backup_to_minio.sh >> /var/log/vault-backup.log 2>&1"

# Cleanup cron (daily at 3 AM)
CLEANUP_CRON="0 3 * * * $SCRIPT_DIR/cleanup_logs.sh >> /var/log/cleanup.log 2>&1"

# Remove old entries and add new ones
(crontab -l 2>/dev/null | grep -v "backup_to_minio.sh" | grep -v "cleanup_logs.sh"; echo "$BACKUP_CRON"; echo "$CLEANUP_CRON") | crontab -

echo "Cron jobs configured:"
crontab -l | grep -E "(backup_to_minio|cleanup_logs)"

# Setup journald limits
echo ""
echo "Configuring journald size limits..."
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/size-limit.conf << 'EOF'
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=100M
MaxRetentionSec=2week
SystemMaxFileSize=50M
EOF

systemctl restart systemd-journald 2>/dev/null || true

# Setup Vault log rotation
echo "Configuring Vault log rotation..."
cat > /etc/logrotate.d/vault << 'EOF'
/var/log/vault/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 vault vault
    sharedscripts
    postrotate
        systemctl reload vault 2>/dev/null || true
    endscript
}
EOF

echo ""
echo "=== Cron Setup Complete ==="
echo "- Hourly backups to MinIO"
echo "- Daily log cleanup at 3 AM"
echo "- Journald limited to 500MB"
echo "- Vault logs rotated daily, kept 7 days"
