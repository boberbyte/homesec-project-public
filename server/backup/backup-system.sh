#!/bin/bash
################################################################################
# HomeSec System Backup Script
# Backs up all critical system configurations and data
################################################################################

# Configuration
BACKUP_ROOT="/mnt/storage/backups"
BACKUP_DIR="${BACKUP_ROOT}/daily"
DATE=$(date +%Y%m%d)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="homesec-backup-${DATE}.tar.gz"
LOG_FILE="/var/log/backup.log"
RETENTION_DAYS=7

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log "=========================================="
log "Starting HomeSec System Backup"
log "Backup timestamp: ${TIMESTAMP}"
log "=========================================="

# Create temporary backup directory
TMP_BACKUP_DIR="/tmp/homesec-backup-${TIMESTAMP}"
mkdir -p "${TMP_BACKUP_DIR}"

# Ensure backup directories exist
mkdir -p "${BACKUP_DIR}"
mkdir -p "${BACKUP_ROOT}/config"

################################################################################
# 1. Backup System Configuration Files
################################################################################
log "Backing up system configuration files..."

mkdir -p "${TMP_BACKUP_DIR}/system"

# Essential system configs
cp -r /etc/fstab "${TMP_BACKUP_DIR}/system/" 2>/dev/null
cp -r /etc/hosts "${TMP_BACKUP_DIR}/system/" 2>/dev/null
cp -r /etc/hostname "${TMP_BACKUP_DIR}/system/" 2>/dev/null
cp -r /etc/resolv.conf "${TMP_BACKUP_DIR}/system/" 2>/dev/null
cp -r /etc/sysctl.conf "${TMP_BACKUP_DIR}/system/" 2>/dev/null

# Network configuration
cp -r /etc/sysconfig/network-scripts/ "${TMP_BACKUP_DIR}/system/" 2>/dev/null

log_success "System configuration backed up"

################################################################################
# 2. Backup DNS (BIND) Configuration
################################################################################
log "Backing up DNS configuration..."

if [ -d /etc/named ]; then
    mkdir -p "${TMP_BACKUP_DIR}/bind"
    cp -r /etc/named.conf "${TMP_BACKUP_DIR}/bind/" 2>/dev/null
    cp -r /etc/named/ "${TMP_BACKUP_DIR}/bind/" 2>/dev/null
    cp -r /var/named/zones/ "${TMP_BACKUP_DIR}/bind/" 2>/dev/null

    # Copy to config backup location
    tar -czf "${BACKUP_ROOT}/config/bind/bind-${DATE}.tar.gz" -C "${TMP_BACKUP_DIR}" bind/
    log_success "DNS configuration backed up"
else
    log_warning "BIND not installed or not configured"
fi

################################################################################
# 3. Backup Samba/NFS Configuration
################################################################################
log "Backing up NAS configuration..."

if [ -f /etc/samba/smb.conf ]; then
    mkdir -p "${TMP_BACKUP_DIR}/samba"
    cp -r /etc/samba/ "${TMP_BACKUP_DIR}/samba/" 2>/dev/null
    tar -czf "${BACKUP_ROOT}/config/samba/samba-${DATE}.tar.gz" -C "${TMP_BACKUP_DIR}" samba/
    log_success "Samba configuration backed up"
fi

if [ -f /etc/exports ]; then
    mkdir -p "${TMP_BACKUP_DIR}/nfs"
    cp /etc/exports "${TMP_BACKUP_DIR}/nfs/" 2>/dev/null
    cp -r /etc/exports.d/ "${TMP_BACKUP_DIR}/nfs/" 2>/dev/null
    log_success "NFS configuration backed up"
fi

################################################################################
# 4. Backup Firewall Rules
################################################################################
log "Backing up firewall rules..."

mkdir -p "${TMP_BACKUP_DIR}/firewall"

# Firewalld
if systemctl is-active --quiet firewalld; then
    firewall-cmd --list-all > "${TMP_BACKUP_DIR}/firewall/firewalld-rules.txt"
    cp -r /etc/firewalld/ "${TMP_BACKUP_DIR}/firewall/" 2>/dev/null
    log_success "Firewalld rules backed up"
fi

# iptables (fallback)
iptables-save > "${TMP_BACKUP_DIR}/firewall/iptables-rules.txt"

################################################################################
# 5. Backup Elasticsearch/Kibana Configuration
################################################################################
log "Backing up ELK configuration..."

if [ -d /var/lib/containers ]; then
    mkdir -p "${TMP_BACKUP_DIR}/elk"

    # Elasticsearch config
    podman exec elasticsearch cat /usr/share/elasticsearch/config/elasticsearch.yml > "${TMP_BACKUP_DIR}/elk/elasticsearch.yml" 2>/dev/null

    # Kibana config
    podman exec kibana cat /usr/share/kibana/config/kibana.yml > "${TMP_BACKUP_DIR}/elk/kibana.yml" 2>/dev/null

    tar -czf "${BACKUP_ROOT}/config/elasticsearch/elk-${DATE}.tar.gz" -C "${TMP_BACKUP_DIR}" elk/
    log_success "ELK configuration backed up"
fi

################################################################################
# 6. Backup Filebeat/Metricbeat Configuration
################################################################################
log "Backing up Beats configuration..."

if [ -d /etc/filebeat ]; then
    mkdir -p "${TMP_BACKUP_DIR}/beats"
    cp -r /etc/filebeat/ "${TMP_BACKUP_DIR}/beats/" 2>/dev/null
    cp -r /etc/metricbeat/ "${TMP_BACKUP_DIR}/beats/" 2>/dev/null
    tar -czf "${BACKUP_ROOT}/config/filebeat/beats-${DATE}.tar.gz" -C "${TMP_BACKUP_DIR}" beats/
    log_success "Beats configuration backed up"
fi

################################################################################
# 7. Backup Rock Pi Configurations (via SSH)
################################################################################
log "Backing up Rock Pi configurations..."

# Rock Pi 4 SE (IDS)
if ping -c 1 -W 2 192.168.20.20 &>/dev/null; then
    mkdir -p "${TMP_BACKUP_DIR}/rockpi4-ids"

    # Suricata config
    scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        root@192.168.20.20:/etc/suricata/suricata.yaml \
        "${TMP_BACKUP_DIR}/rockpi4-ids/" 2>/dev/null

    # Filebeat config
    scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        root@192.168.20.20:/etc/filebeat/filebeat.yml \
        "${TMP_BACKUP_DIR}/rockpi4-ids/" 2>/dev/null

    tar -czf "${BACKUP_ROOT}/config/suricata/rockpi4-ids-${DATE}.tar.gz" -C "${TMP_BACKUP_DIR}" rockpi4-ids/
    log_success "Rock Pi 4 SE configuration backed up"
else
    log_warning "Rock Pi 4 SE not reachable, skipping"
fi

# Rock Pi E (IPS) - Note: may not have IP, use serial or skip
# Uncomment if Rock Pi E has management IP
# if ping -c 1 -W 2 192.168.20.21 &>/dev/null; then
#     mkdir -p "${TMP_BACKUP_DIR}/rockpi-e-ips"
#     scp -q root@192.168.20.21:/etc/suricata/suricata.yaml "${TMP_BACKUP_DIR}/rockpi-e-ips/"
#     log_success "Rock Pi E configuration backed up"
# fi

################################################################################
# 8. Backup OpenWrt Router Configuration (via SSH)
################################################################################
log "Backing up OpenWrt configuration..."

if ping -c 1 -W 2 192.168.20.1 &>/dev/null; then
    mkdir -p "${TMP_BACKUP_DIR}/openwrt"

    # UCI configs
    scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        root@192.168.20.1:/etc/config/network \
        "${TMP_BACKUP_DIR}/openwrt/" 2>/dev/null

    scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        root@192.168.20.1:/etc/config/dhcp \
        "${TMP_BACKUP_DIR}/openwrt/" 2>/dev/null

    scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        root@192.168.20.1:/etc/config/firewall \
        "${TMP_BACKUP_DIR}/openwrt/" 2>/dev/null

    scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        root@192.168.20.1:/etc/config/wireless \
        "${TMP_BACKUP_DIR}/openwrt/" 2>/dev/null

    tar -czf "${BACKUP_ROOT}/config/openwrt/openwrt-${DATE}.tar.gz" -C "${TMP_BACKUP_DIR}" openwrt/
    log_success "OpenWrt configuration backed up"
else
    log_warning "OpenWrt router not reachable, skipping"
fi

################################################################################
# 9. Backup Cron Jobs and Scripts
################################################################################
log "Backing up cron jobs and scripts..."

mkdir -p "${TMP_BACKUP_DIR}/cron"
crontab -l > "${TMP_BACKUP_DIR}/cron/root-crontab.txt" 2>/dev/null
cp -r /etc/cron.d/ "${TMP_BACKUP_DIR}/cron/" 2>/dev/null
cp -r /etc/cron.daily/ "${TMP_BACKUP_DIR}/cron/" 2>/dev/null
cp -r /etc/cron.weekly/ "${TMP_BACKUP_DIR}/cron/" 2>/dev/null

mkdir -p "${TMP_BACKUP_DIR}/scripts"
cp -r /usr/local/bin/backup-*.sh "${TMP_BACKUP_DIR}/scripts/" 2>/dev/null
cp -r /usr/local/bin/snapshot-*.sh "${TMP_BACKUP_DIR}/scripts/" 2>/dev/null

log_success "Cron jobs and scripts backed up"

################################################################################
# 10. Create Compressed Archive
################################################################################
log "Creating compressed archive..."

cd /tmp
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" "homesec-backup-${TIMESTAMP}/"

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    log_success "Backup archive created: ${BACKUP_FILE} (${BACKUP_SIZE})"
else
    log_error "Failed to create backup archive"
    exit 1
fi

# Clean up temporary directory
rm -rf "${TMP_BACKUP_DIR}"

################################################################################
# 11. Retention Management
################################################################################
log "Managing backup retention (keeping last ${RETENTION_DAYS} days)..."

find "${BACKUP_DIR}" -name "homesec-backup-*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
REMOVED_COUNT=$(find "${BACKUP_DIR}" -name "homesec-backup-*.tar.gz" -type f -mtime +${RETENTION_DAYS} | wc -l)

if [ ${REMOVED_COUNT} -gt 0 ]; then
    log "Removed ${REMOVED_COUNT} old backup(s)"
fi

################################################################################
# 12. Verify Backup
################################################################################
log "Verifying backup integrity..."

if tar -tzf "${BACKUP_DIR}/${BACKUP_FILE}" >/dev/null 2>&1; then
    log_success "Backup integrity verified"
else
    log_error "Backup integrity check failed!"
    exit 1
fi

################################################################################
# 13. Summary
################################################################################
TOTAL_BACKUPS=$(ls -1 "${BACKUP_DIR}"/homesec-backup-*.tar.gz 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)

log "=========================================="
log "Backup completed successfully"
log "Total backups: ${TOTAL_BACKUPS}"
log "Total size: ${TOTAL_SIZE}"
log "=========================================="

exit 0
