#!/bin/bash
################################################################################
# Backup Verification Script
# Verifies integrity of backups and sends alerts if issues found
################################################################################

# Configuration
BACKUP_ROOT="/mnt/storage/backups"
LOG_FILE="/var/log/backup-verify.log"
ES_HOST="localhost:9200"
ALERT_EMAIL="admin@homesec.local"  # Configure if email alerts needed

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Starting Backup Verification"
log "=========================================="

################################################################################
# 1. Check backup directory exists
################################################################################
log "Checking backup directories..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if [ -d "$BACKUP_ROOT" ]; then
    log_success "Backup root directory exists: $BACKUP_ROOT"
else
    log_error "Backup root directory not found: $BACKUP_ROOT"
    exit 1
fi

################################################################################
# 2. Check daily backups
################################################################################
log "Checking daily backups..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

LATEST_BACKUP=$(ls -t "${BACKUP_ROOT}/daily"/homesec-backup-*.tar.gz 2>/dev/null | head -1)

if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 86400 ))
    BACKUP_SIZE=$(du -h "$LATEST_BACKUP" | cut -f1)

    if [ $BACKUP_AGE -le 1 ]; then
        log_success "Latest backup found: $(basename $LATEST_BACKUP) (${BACKUP_SIZE}, ${BACKUP_AGE} days old)"

        # Verify archive integrity
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        if tar -tzf "$LATEST_BACKUP" >/dev/null 2>&1; then
            log_success "Backup archive integrity verified"
        else
            log_error "Backup archive is corrupted: $LATEST_BACKUP"
        fi
    else
        log_error "Latest backup is too old (${BACKUP_AGE} days)"
    fi
else
    log_error "No daily backups found in ${BACKUP_ROOT}/daily/"
fi

################################################################################
# 3. Check Elasticsearch snapshots
################################################################################
log "Checking Elasticsearch snapshots..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if curl -s -f "http://${ES_HOST}" > /dev/null 2>&1; then
    SNAPSHOT_INFO=$(curl -s "http://${ES_HOST}/_snapshot/homesec_backup/_all" 2>/dev/null)

    if [ -n "$SNAPSHOT_INFO" ]; then
        SNAPSHOT_COUNT=$(echo "$SNAPSHOT_INFO" | jq -r '.snapshots | length' 2>/dev/null || echo "0")

        if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
            LATEST_SNAPSHOT=$(echo "$SNAPSHOT_INFO" | jq -r '.snapshots[-1].snapshot' 2>/dev/null)
            SNAPSHOT_STATE=$(echo "$SNAPSHOT_INFO" | jq -r '.snapshots[-1].state' 2>/dev/null)
            SNAPSHOT_DATE=$(echo "$LATEST_SNAPSHOT" | sed -n 's/snapshot_\([0-9]\{8\}\).*/\1/p')

            if [ "$SNAPSHOT_STATE" == "SUCCESS" ]; then
                log_success "Elasticsearch snapshots found: ${SNAPSHOT_COUNT} total, latest: ${LATEST_SNAPSHOT}"
            else
                log_error "Latest Elasticsearch snapshot is not in SUCCESS state: ${SNAPSHOT_STATE}"
            fi
        else
            log_error "No Elasticsearch snapshots found"
        fi
    else
        log_warning "Could not retrieve Elasticsearch snapshot information"
    fi
else
    log_warning "Elasticsearch is not running, skipping snapshot check"
fi

################################################################################
# 4. Check backup disk space
################################################################################
log "Checking backup disk space..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

BACKUP_USAGE=$(df -h "$BACKUP_ROOT" | tail -1 | awk '{print $5}' | tr -d '%')

if [ "$BACKUP_USAGE" -lt 80 ]; then
    log_success "Backup disk usage is healthy: ${BACKUP_USAGE}%"
elif [ "$BACKUP_USAGE" -lt 90 ]; then
    log_warning "Backup disk usage is high: ${BACKUP_USAGE}%"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    log_error "Backup disk usage is critical: ${BACKUP_USAGE}%"
fi

################################################################################
# 5. Check config backups
################################################################################
log "Checking configuration backups..."

CONFIG_DIRS=("bind" "samba" "elasticsearch" "openwrt" "suricata")

for dir in "${CONFIG_DIRS[@]}"; do
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    CONFIG_PATH="${BACKUP_ROOT}/config/${dir}"

    if [ -d "$CONFIG_PATH" ]; then
        FILE_COUNT=$(ls -1 "$CONFIG_PATH"/*.tar.gz 2>/dev/null | wc -l)

        if [ "$FILE_COUNT" -gt 0 ]; then
            LATEST_FILE=$(ls -t "$CONFIG_PATH"/*.tar.gz 2>/dev/null | head -1)
            FILE_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_FILE")) / 86400 ))

            if [ $FILE_AGE -le 2 ]; then
                log_success "${dir} config backup OK (${FILE_COUNT} files, latest ${FILE_AGE} days old)"
            else
                log_warning "${dir} config backup outdated (${FILE_AGE} days old)"
            fi
        else
            log_warning "No ${dir} config backups found"
        fi
    else
        log_warning "${dir} config backup directory not found"
    fi
done

################################################################################
# 6. Check LVM snapshots
################################################################################
log "Checking LVM snapshots..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

SNAPSHOT_COUNT=$(lvs --noheadings -o lv_name vg_storage 2>/dev/null | grep "_snap" | wc -l)

if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
    log_success "Found ${SNAPSHOT_COUNT} LVM snapshot(s)"

    # Check snapshot usage
    while read -r snap percent; do
        if (( $(echo "$percent >= 80" | bc -l) )); then
            log_warning "Snapshot ${snap} is ${percent}% full"
        fi
    done < <(lvs --noheadings -o lv_name,snap_percent vg_storage 2>/dev/null | grep "_snap" | awk '{print $1, $2}')
else
    log_warning "No LVM snapshots found"
fi

################################################################################
# 7. Summary and alerts
################################################################################
log "=========================================="
log "Verification Summary:"
log "  Total checks: ${TOTAL_CHECKS}"
log "  Passed: ${PASSED_CHECKS}"
log "  Failed: ${FAILED_CHECKS}"
log "=========================================="

# Send alert if failures detected (requires configured mail system)
if [ $FAILED_CHECKS -gt 0 ]; then
    log_error "Backup verification found ${FAILED_CHECKS} issue(s)"

    # Uncomment to enable email alerts
    # if command -v mail &> /dev/null; then
    #     echo "Backup verification failed with ${FAILED_CHECKS} issue(s). Check ${LOG_FILE} for details." | \
    #         mail -s "HomeSec Backup Verification FAILED" "$ALERT_EMAIL"
    # fi

    exit 1
else
    log_success "All backup verifications passed"
    exit 0
fi
