#!/bin/bash
################################################################################
# Suricata Rules Update Script
# Updates detection rules on IDS and IPS systems
################################################################################

# Configuration
LOG_FILE="/var/log/maintenance.log"
IDS_HOST="192.168.20.20"
IPS_HOST="192.168.20.21"  # If Rock Pi E has IP, otherwise use serial
UPDATE_IDS=true
UPDATE_IPS=true

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --ids-only)
            UPDATE_IPS=false
            shift
            ;;
        --ips-only)
            UPDATE_IDS=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--ids-only|--ips-only]"
            exit 1
            ;;
    esac
done

log "=========================================="
log "Suricata Rules Update"
log "=========================================="

################################################################################
# Update function
################################################################################
update_suricata_rules() {
    local HOST=$1
    local NAME=$2

    log "Updating rules on ${NAME} (${HOST})..."

    # Check if host is reachable
    if ! ping -c 1 -W 2 "$HOST" > /dev/null 2>&1; then
        log_error "${NAME} is not reachable at ${HOST}"
        return 1
    fi

    # Run suricata-update via SSH
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$HOST" "suricata-update" 2>&1 | tee -a "$LOG_FILE"; then
        log_ok "Rules updated on ${NAME}"

        # Test configuration
        if ssh -o ConnectTimeout=10 root@"$HOST" "suricata -T -c /etc/suricata/suricata.yaml" > /dev/null 2>&1; then
            log_ok "Configuration test passed on ${NAME}"

            # Reload Suricata
            if ssh -o ConnectTimeout=10 root@"$HOST" "systemctl reload suricata" 2>&1 | tee -a "$LOG_FILE"; then
                log_ok "Suricata reloaded on ${NAME}"
                return 0
            else
                log_error "Failed to reload Suricata on ${NAME}"
                return 1
            fi
        else
            log_error "Configuration test failed on ${NAME}"
            ssh -o ConnectTimeout=10 root@"$HOST" "suricata -T -c /etc/suricata/suricata.yaml" 2>&1 | tee -a "$LOG_FILE"
            return 1
        fi
    else
        log_error "Failed to update rules on ${NAME}"
        return 1
    fi
}

################################################################################
# Update IDS (Rock Pi 4 SE)
################################################################################
if [ "$UPDATE_IDS" = true ]; then
    update_suricata_rules "$IDS_HOST" "Rock Pi 4 SE (IDS)"
    IDS_RESULT=$?
fi

################################################################################
# Update IPS (Rock Pi E)
################################################################################
if [ "$UPDATE_IPS" = true ]; then
    # Note: Rock Pi E may not have IP if running as transparent bridge
    # Skip if not reachable
    if ping -c 1 -W 2 "$IPS_HOST" > /dev/null 2>&1; then
        update_suricata_rules "$IPS_HOST" "Rock Pi E (IPS)"
        IPS_RESULT=$?
    else
        log_warning "Rock Pi E (IPS) not reachable via network, skipping"
        log_warning "Manual update required via serial console if needed"
        IPS_RESULT=0
    fi
fi

################################################################################
# Summary
################################################################################
log "=========================================="

if [ "$UPDATE_IDS" = true ] && [ "$IDS_RESULT" -eq 0 ]; then
    log_ok "IDS rules update completed successfully"
elif [ "$UPDATE_IDS" = true ]; then
    log_error "IDS rules update failed"
fi

if [ "$UPDATE_IPS" = true ] && [ "$IPS_RESULT" -eq 0 ]; then
    log_ok "IPS rules update completed successfully"
elif [ "$UPDATE_IPS" = true ]; then
    log_error "IPS rules update failed"
fi

log "=========================================="

# Exit with error if any update failed
if ([ "$UPDATE_IDS" = true ] && [ "$IDS_RESULT" -ne 0 ]) || \
   ([ "$UPDATE_IPS" = true ] && [ "$IPS_RESULT" -ne 0 ]); then
    exit 1
fi

exit 0
