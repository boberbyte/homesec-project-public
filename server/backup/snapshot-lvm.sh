#!/bin/bash
################################################################################
# LVM Snapshot Script
# Creates LVM snapshots for quick backups and rollbacks
################################################################################

# Configuration
VG_NAME="vg_storage"
SNAPSHOT_SIZE="10G"
LOG_FILE="/var/log/lvm-snapshot.log"

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

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Usage function
usage() {
    echo "Usage: $0 <lv_name|all> [snapshot_size]"
    echo ""
    echo "Examples:"
    echo "  $0 lv_shared           # Snapshot lv_shared with default 10G size"
    echo "  $0 lv_shared 20G       # Snapshot lv_shared with 20G size"
    echo "  $0 all                 # Snapshot all LVs"
    echo ""
    echo "Available LVs:"
    lvs --noheadings -o lv_name "${VG_NAME}" 2>/dev/null | sed 's/^/  /'
    exit 1
}

# Check arguments
if [ $# -lt 1 ]; then
    usage
fi

LV_INPUT="$1"
SNAPSHOT_SIZE="${2:-10G}"

################################################################################
# Create snapshot for a single LV
################################################################################
create_snapshot() {
    local LV_NAME="$1"
    local SNAP_SIZE="$2"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local SNAP_NAME="${LV_NAME}_snap_${TIMESTAMP}"

    log "=========================================="
    log "Creating snapshot for ${LV_NAME}"
    log "=========================================="

    # Check if LV exists
    if ! lvs "${VG_NAME}/${LV_NAME}" &>/dev/null; then
        log_error "Logical volume ${LV_NAME} does not exist in ${VG_NAME}"
        return 1
    fi

    # Check for existing snapshots
    EXISTING_SNAPS=$(lvs --noheadings -o lv_name "${VG_NAME}" | grep "${LV_NAME}_snap" | wc -l)
    if [ $EXISTING_SNAPS -gt 0 ]; then
        log_warning "Found ${EXISTING_SNAPS} existing snapshot(s) for ${LV_NAME}"
        log "Listing existing snapshots:"
        lvs --noheadings -o lv_name,lv_size,snap_percent "${VG_NAME}" | grep "${LV_NAME}_snap" | tee -a "$LOG_FILE"
    fi

    # Check VG free space
    VG_FREE=$(vgs --noheadings --units g -o vg_free "${VG_NAME}" | tr -d ' G')
    SNAP_SIZE_NUM=$(echo "${SNAP_SIZE}" | tr -d 'G')

    if (( $(echo "${VG_FREE} < ${SNAP_SIZE_NUM}" | bc -l) )); then
        log_error "Not enough free space in ${VG_NAME}. Required: ${SNAP_SIZE}, Available: ${VG_FREE}G"
        return 1
    fi

    # Create snapshot
    log "Creating snapshot: ${SNAP_NAME} (${SNAP_SIZE})..."

    if lvcreate -L "${SNAP_SIZE}" -s -n "${SNAP_NAME}" "/dev/${VG_NAME}/${LV_NAME}"; then
        log_success "Snapshot ${SNAP_NAME} created successfully"

        # Display snapshot info
        log "Snapshot information:"
        lvs --units g -o lv_name,lv_size,origin,snap_percent,lv_attr "/dev/${VG_NAME}/${SNAP_NAME}" | tee -a "$LOG_FILE"

        return 0
    else
        log_error "Failed to create snapshot ${SNAP_NAME}"
        return 1
    fi
}

################################################################################
# Main logic
################################################################################

if [ "$LV_INPUT" == "all" ]; then
    log "Creating snapshots for all logical volumes in ${VG_NAME}"

    # Get list of all LVs (excluding existing snapshots)
    LV_LIST=$(lvs --noheadings -o lv_name "${VG_NAME}" | grep -v "_snap" | tr -d ' ')

    SUCCESS_COUNT=0
    FAIL_COUNT=0

    for LV in $LV_LIST; do
        if create_snapshot "$LV" "$SNAPSHOT_SIZE"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done

    log "=========================================="
    log "Snapshot summary:"
    log "  Successful: ${SUCCESS_COUNT}"
    log "  Failed: ${FAIL_COUNT}"
    log "=========================================="

    if [ $FAIL_COUNT -gt 0 ]; then
        exit 1
    fi

else
    # Create snapshot for single LV
    create_snapshot "$LV_INPUT" "$SNAPSHOT_SIZE"
    exit $?
fi

exit 0
