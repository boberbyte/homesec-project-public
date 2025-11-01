# Backup System

## Overview

Automated backup system for all HomeSec components with multiple backup strategies, retention policies, and verification.

**Backup Location**: /mnt/storage/backups (RAID array)
**Backup Schedule**: Daily automated backups via cron
**Retention**: 7 daily, 4 weekly, 12 monthly backups

## Backup Strategy

### What Gets Backed Up

| Component | Backup Type | Frequency | Retention |
|-----------|-------------|-----------|-----------|
| **System configs** | File copy | Daily | 30 days |
| **Elasticsearch data** | Snapshot API | Daily | 30 days |
| **Suricata configs** | rsync | Daily | 30 days |
| **DNS zones** | File copy | Daily | 30 days |
| **NAS configs** | File copy | Daily | 30 days |
| **Scripts** | Git + tarball | Daily | 30 days |
| **VM images** | LVM snapshot | Weekly | 4 weeks |
| **User data** | rsync | Daily | 30 days |

### Backup Locations

```
/mnt/storage/backups/
├── config/           # System configuration files
│   ├── elasticsearch/
│   ├── kibana/
│   ├── suricata/
│   ├── bind/
│   ├── samba/
│   └── openwrt/
├── elasticsearch/    # Elasticsearch snapshots
├── vm/              # VM backups
├── daily/           # Daily automated backups
├── weekly/          # Weekly archives
└── monthly/         # Monthly archives
```

## Installation

### 1. Create Backup Directory Structure

```bash
# Create directories
sudo mkdir -p /mnt/storage/backups/{config,elasticsearch,vm,daily,weekly,monthly}
sudo mkdir -p /mnt/storage/backups/config/{elasticsearch,kibana,suricata,bind,samba,openwrt,filebeat,metricbeat}

# Set permissions
sudo chmod 700 /mnt/storage/backups
sudo chown -R root:root /mnt/storage/backups
```

### 2. Install Backup Scripts

```bash
# Copy scripts to /usr/local/bin
sudo cp backup-system.sh /usr/local/bin/
sudo cp backup-elasticsearch.sh /usr/local/bin/
sudo cp backup-configs.sh /usr/local/bin/
sudo cp snapshot-lvm.sh /usr/local/bin/
sudo cp verify-backups.sh /usr/local/bin/

# Make executable
sudo chmod +x /usr/local/bin/backup-*.sh
sudo chmod +x /usr/local/bin/snapshot-lvm.sh
sudo chmod +x /usr/local/bin/verify-backups.sh
```

### 3. Configure Elasticsearch Snapshot Repository

```bash
# Create snapshot repository in Elasticsearch
curl -X PUT "http://localhost:9200/_snapshot/homesec_backup" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/mnt/storage/backups/elasticsearch",
    "compress": true
  }
}'

# Verify repository
curl -X GET "http://localhost:9200/_snapshot/homesec_backup?pretty"
```

### 4. Set Up Cron Jobs

```bash
# Edit root crontab
sudo crontab -e

# Add backup jobs:
# Daily full backup at 2 AM
0 2 * * * /usr/local/bin/backup-system.sh >> /var/log/backup.log 2>&1

# Daily Elasticsearch backup at 3 AM
0 3 * * * /usr/local/bin/backup-elasticsearch.sh >> /var/log/backup.log 2>&1

# Weekly verification on Sunday at 4 AM
0 4 * * 0 /usr/local/bin/verify-backups.sh >> /var/log/backup-verify.log 2>&1

# Weekly VM snapshot on Sunday at 1 AM
0 1 * * 0 /usr/local/bin/snapshot-lvm.sh all >> /var/log/lvm-snapshot.log 2>&1

# Save and exit
```

### 5. Test Backups

```bash
# Test manual backup
sudo /usr/local/bin/backup-system.sh

# Check backup log
sudo tail -f /var/log/backup.log

# Verify files created
ls -lah /mnt/storage/backups/daily/
```

## Backup Scripts

### backup-system.sh
Main backup script that orchestrates all backups:
- System configuration files
- Service configs (Samba, NFS, BIND)
- Rock Pi configs (via SSH)
- OpenWrt config (via SSH)
- Retention management

### backup-elasticsearch.sh
Elasticsearch-specific backup:
- Creates snapshot via API
- Manages snapshot retention
- Verifies snapshot integrity

### backup-configs.sh
Lightweight config-only backup:
- Quick config file backup
- Can run more frequently
- Minimal resource usage

### snapshot-lvm.sh
LVM snapshot creation:
- Creates LVM snapshots for VMs
- Manages snapshot retention
- Can be used for quick rollbacks

### verify-backups.sh
Backup verification script:
- Checks backup integrity
- Verifies file counts
- Tests Elasticsearch snapshots
- Sends alerts if issues found

## Manual Backup Operations

### Full System Backup

```bash
# Run full backup manually
sudo /usr/local/bin/backup-system.sh

# Backup to external location
sudo rsync -avz /mnt/storage/backups/ /mnt/external-drive/homesec-backups/
```

### Backup Specific Component

```bash
# Backup only Elasticsearch
sudo /usr/local/bin/backup-elasticsearch.sh

# Backup only configs
sudo /usr/local/bin/backup-configs.sh

# Backup specific config
sudo tar -czf /mnt/storage/backups/config/bind-$(date +%Y%m%d).tar.gz /etc/named*
```

### Create LVM Snapshot

```bash
# Snapshot specific volume
sudo /usr/local/bin/snapshot-lvm.sh lv_shared

# Snapshot all volumes
sudo /usr/local/bin/snapshot-lvm.sh all
```

## Restore Procedures

### Restore System Configuration

```bash
# List available backups
ls -lah /mnt/storage/backups/daily/

# Extract specific backup
sudo tar -xzf /mnt/storage/backups/daily/homesec-backup-20240115.tar.gz -C /tmp/

# Restore specific config
sudo cp /tmp/backup/etc/named.conf /etc/named.conf

# Verify and restart service
sudo named-checkconf
sudo systemctl restart named
```

### Restore Elasticsearch Data

```bash
# List available snapshots
curl -X GET "http://localhost:9200/_snapshot/homesec_backup/_all?pretty"

# Restore specific snapshot
curl -X POST "http://localhost:9200/_snapshot/homesec_backup/snapshot_20240115/_restore" -H 'Content-Type: application/json' -d'
{
  "indices": "*",
  "ignore_unavailable": true,
  "include_global_state": false
}'

# Monitor restore progress
curl -X GET "http://localhost:9200/_recovery?pretty"
```

### Restore from LVM Snapshot

```bash
# List snapshots
sudo lvs

# Mount snapshot to recover files
sudo mkdir -p /mnt/snapshot
sudo mount -o ro /dev/vg_storage/lv_shared_snap /mnt/snapshot

# Copy needed files
sudo cp /mnt/snapshot/path/to/file /destination/

# Or merge snapshot to rollback completely (CAUTION!)
sudo umount /mnt/storage/shared
sudo lvconvert --merge /dev/vg_storage/lv_shared_snap
sudo mount /mnt/storage/shared
```

### Restore Rock Pi Configuration

```bash
# Extract Rock Pi backup
sudo tar -xzf /mnt/storage/backups/daily/rockpi4-ids-20240115.tar.gz -C /tmp/

# Copy to Rock Pi via SCP
scp -r /tmp/backup/etc/suricata/ root@192.168.20.20:/etc/

# SSH to Rock Pi and restart
ssh root@192.168.20.20
systemctl restart suricata
```

## Monitoring Backups

### Check Backup Status

```bash
# View backup log
sudo tail -100 /var/log/backup.log

# Check last backup date
ls -lt /mnt/storage/backups/daily/ | head -5

# Verify backup sizes
du -sh /mnt/storage/backups/*
```

### Monitor Backup Space

```bash
# Check available space
df -h /mnt/storage

# Check backup directory size
du -sh /mnt/storage/backups/

# Detailed breakdown
du -h --max-depth=1 /mnt/storage/backups/ | sort -hr
```

### Backup Alerts

```bash
# Set up alert if backup fails (in backup scripts)
# Sends email or log to monitoring system

# Check for failed backups
grep -i "error\|fail" /var/log/backup.log

# Integrate with ELK for alerting
# See ../monitoring/README.md
```

## Retention Management

Retention is handled automatically by scripts:
- **Daily backups**: Keep last 7 days
- **Weekly backups**: Keep last 4 weeks
- **Monthly backups**: Keep last 12 months

Manual cleanup:
```bash
# Remove old backups manually
find /mnt/storage/backups/daily -type f -mtime +7 -delete

# Remove old Elasticsearch snapshots
curl -X DELETE "http://localhost:9200/_snapshot/homesec_backup/snapshot_20230101"
```

## Offsite Backup

For disaster recovery, periodically copy backups offsite:

### USB Drive Backup

```bash
# Mount USB drive
sudo mount /dev/sdb1 /mnt/usb

# Sync backups
sudo rsync -avz --delete /mnt/storage/backups/ /mnt/usb/homesec-backups/

# Verify
du -sh /mnt/usb/homesec-backups/

# Unmount
sudo umount /mnt/usb
```

### Cloud Backup (Optional)

```bash
# Using rclone to cloud storage (S3, Google Drive, etc.)
# Install rclone
sudo yum install -y rclone

# Configure cloud remote
rclone config

# Sync to cloud (encrypted)
rclone sync /mnt/storage/backups/ remote:homesec-backups/ \
    --crypt-password "your-encryption-password" \
    --exclude "*.tmp"
```

## Troubleshooting

### Backup Script Fails

```bash
# Check log for errors
sudo tail -100 /var/log/backup.log

# Run script manually with verbose output
sudo bash -x /usr/local/bin/backup-system.sh

# Check disk space
df -h /mnt/storage

# Check permissions
ls -la /mnt/storage/backups/
```

### Elasticsearch Snapshot Fails

```bash
# Check snapshot repository
curl -X GET "http://localhost:9200/_snapshot/homesec_backup?pretty"

# Check Elasticsearch logs
sudo podman logs elasticsearch | tail -50

# Verify path permissions
ls -la /mnt/storage/backups/elasticsearch/

# Check cluster health
curl -X GET "http://localhost:9200/_cluster/health?pretty"
```

### LVM Snapshot Issues

```bash
# Check VG space
sudo vgs

# Remove old snapshots to free space
sudo lvs
sudo lvremove /dev/vg_storage/old_snapshot

# Increase snapshot size if needed
sudo lvextend -L +10G /dev/vg_storage/lv_shared_snap
```

## Best Practices

1. **Test restores regularly**: Verify backups can actually be restored
2. **Monitor backup size trends**: Detect abnormal growth
3. **Keep offsite copies**: Protect against site-wide disasters
4. **Document restore procedures**: Clear steps for emergency recovery
5. **Encrypt sensitive backups**: Especially for offsite storage
6. **Automate verification**: Regular automated backup integrity checks
7. **Alert on failures**: Immediate notification if backup fails

## Security

### Backup Permissions

```bash
# Restrict backup directory
sudo chmod 700 /mnt/storage/backups
sudo chown root:root /mnt/storage/backups

# Scripts should run as root
sudo chmod 700 /usr/local/bin/backup-*.sh
```

### Encryption (Optional)

For highly sensitive data:

```bash
# Encrypt backup archive
tar -czf - /path/to/data | openssl enc -aes-256-cbc -salt -out backup-encrypted.tar.gz.enc

# Decrypt when restoring
openssl enc -aes-256-cbc -d -in backup-encrypted.tar.gz.enc | tar -xzf -
```

## Related Documentation

- [NAS Configuration](../nas/README.md)
- [Architecture](../../docs/architecture.md)
- [Troubleshooting](../../docs/troubleshooting.md)
