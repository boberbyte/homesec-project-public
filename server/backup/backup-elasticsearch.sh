#!/bin/bash
################################################################################
# Elasticsearch Snapshot Backup Script
# Creates Elasticsearch snapshots via Snapshot API
################################################################################

# Configuration
ES_HOST="localhost:9200"
SNAPSHOT_REPO="homesec_backup"
SNAPSHOT_NAME="snapshot_$(date +%Y%m%d_%H%M%S)"
RETENTION_DAYS=30
LOG_FILE="/var/log/backup.log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

log "=========================================="
log "Starting Elasticsearch Snapshot Backup"
log "=========================================="

################################################################################
# 1. Check Elasticsearch is running
################################################################################
log "Checking Elasticsearch status..."

if ! curl -s -f "http://${ES_HOST}" > /dev/null; then
    log_error "Elasticsearch is not responding"
    exit 1
fi

log_success "Elasticsearch is running"

################################################################################
# 2. Verify snapshot repository exists
################################################################################
log "Verifying snapshot repository..."

REPO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${ES_HOST}/_snapshot/${SNAPSHOT_REPO}")

if [ "${REPO_STATUS}" != "200" ]; then
    log_error "Snapshot repository '${SNAPSHOT_REPO}' does not exist"
    log "Creating repository..."

    curl -X PUT "http://${ES_HOST}/_snapshot/${SNAPSHOT_REPO}" \
        -H 'Content-Type: application/json' -d'{
        "type": "fs",
        "settings": {
            "location": "/mnt/storage/backups/elasticsearch",
            "compress": true
        }
    }'

    if [ $? -ne 0 ]; then
        log_error "Failed to create snapshot repository"
        exit 1
    fi

    log_success "Snapshot repository created"
fi

################################################################################
# 3. Create snapshot
################################################################################
log "Creating snapshot: ${SNAPSHOT_NAME}..."

RESPONSE=$(curl -s -X PUT "http://${ES_HOST}/_snapshot/${SNAPSHOT_REPO}/${SNAPSHOT_NAME}?wait_for_completion=true" \
    -H 'Content-Type: application/json' -d'{
    "indices": "*",
    "ignore_unavailable": true,
    "include_global_state": false,
    "metadata": {
        "taken_by": "backup-elasticsearch.sh",
        "taken_at": "'$(date -Iseconds)'"
    }
}')

if echo "$RESPONSE" | grep -q '"state":"SUCCESS"'; then
    log_success "Snapshot created successfully"
else
    log_error "Snapshot creation failed"
    echo "$RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

################################################################################
# 4. Verify snapshot
################################################################################
log "Verifying snapshot..."

SNAPSHOT_INFO=$(curl -s "http://${ES_HOST}/_snapshot/${SNAPSHOT_REPO}/${SNAPSHOT_NAME}")

if echo "$SNAPSHOT_INFO" | grep -q '"state":"SUCCESS"'; then
    SNAPSHOT_SIZE=$(echo "$SNAPSHOT_INFO" | jq -r '.snapshots[0].stats.total.size_in_bytes' 2>/dev/null || echo "unknown")
    SNAPSHOT_SIZE_HR=$(numfmt --to=iec-i --suffix=B $SNAPSHOT_SIZE 2>/dev/null || echo "unknown")
    INDICES_COUNT=$(echo "$SNAPSHOT_INFO" | jq -r '.snapshots[0].indices | length' 2>/dev/null || echo "unknown")

    log_success "Snapshot verified: ${INDICES_COUNT} indices, ${SNAPSHOT_SIZE_HR}"
else
    log_error "Snapshot verification failed"
    exit 1
fi

################################################################################
# 5. Retention management
################################################################################
log "Managing snapshot retention (keeping last ${RETENTION_DAYS} days)..."

# Get list of snapshots
SNAPSHOTS=$(curl -s "http://${ES_HOST}/_snapshot/${SNAPSHOT_REPO}/_all" | \
    jq -r '.snapshots[] | select(.snapshot | startswith("snapshot_")) | .snapshot' 2>/dev/null)

DELETED_COUNT=0

for snapshot in $SNAPSHOTS; do
    # Extract date from snapshot name (snapshot_YYYYMMDD_HHMMSS)
    SNAPSHOT_DATE=$(echo "$snapshot" | sed -n 's/snapshot_\([0-9]\{8\}\)_.*/\1/p')

    if [ -n "$SNAPSHOT_DATE" ]; then
        # Calculate age in days
        SNAPSHOT_EPOCH=$(date -d "$SNAPSHOT_DATE" +%s 2>/dev/null)
        CURRENT_EPOCH=$(date +%s)
        AGE_DAYS=$(( (CURRENT_EPOCH - SNAPSHOT_EPOCH) / 86400 ))

        if [ $AGE_DAYS -gt $RETENTION_DAYS ]; then
            log "Deleting old snapshot: $snapshot (${AGE_DAYS} days old)"
            curl -s -X DELETE "http://${ES_HOST}/_snapshot/${SNAPSHOT_REPO}/${snapshot}" > /dev/null
            DELETED_COUNT=$((DELETED_COUNT + 1))
        fi
    fi
done

if [ $DELETED_COUNT -gt 0 ]; then
    log "Deleted ${DELETED_COUNT} old snapshot(s)"
else
    log "No old snapshots to delete"
fi

################################################################################
# 6. Summary
################################################################################
TOTAL_SNAPSHOTS=$(curl -s "http://${ES_HOST}/_snapshot/${SNAPSHOT_REPO}/_all" | \
    jq -r '.snapshots | length' 2>/dev/null || echo "unknown")

log "=========================================="
log "Elasticsearch backup completed"
log "Snapshot name: ${SNAPSHOT_NAME}"
log "Total snapshots: ${TOTAL_SNAPSHOTS}"
log "=========================================="

exit 0
