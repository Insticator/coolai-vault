#!/bin/bash
# System Log Cleanup Script
# Prevents storage overflow from log accumulation

set -e

echo "=== Log Cleanup Started: $(date) ==="

# Clean old journal logs
echo "Cleaning journal logs..."
journalctl --vacuum-time=7d 2>/dev/null || true
journalctl --vacuum-size=500M 2>/dev/null || true

# Clean old log files
echo "Cleaning old log files..."
find /var/log -type f -name "*.gz" -mtime +7 -delete 2>/dev/null || true
find /var/log -type f -name "*.old" -mtime +7 -delete 2>/dev/null || true
find /var/log -type f -name "*.[0-9]" -mtime +7 -delete 2>/dev/null || true
find /var/log -type f -name "*.[0-9].gz" -mtime +7 -delete 2>/dev/null || true

# Truncate large active logs (over 100MB)
for logfile in /var/log/syslog /var/log/auth.log /var/log/kern.log /var/log/vault/audit.log; do
    if [ -f "$logfile" ]; then
        SIZE=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 104857600 ]; then
            echo "Truncating: $logfile"
            truncate -s 10M "$logfile"
        fi
    fi
done

# Clean apt cache
apt-get clean 2>/dev/null || true

# Clean temp files
find /tmp -type f -mtime +7 -delete 2>/dev/null || true
find /var/tmp -type f -mtime +7 -delete 2>/dev/null || true

echo ""
echo "Disk usage: $(df -h / | tail -1 | awk '{print $5}')"
echo "=== Log Cleanup Complete ==="
