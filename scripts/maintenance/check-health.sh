#!/bin/bash
################################################################################
# HomeSec Health Check Script
# Checks health of all components and alerts if issues found
################################################################################

# Configuration
LOG_FILE="/var/log/health-check.log"
ALERT_EMAIL="admin@homesec.local"
DISK_WARN_THRESHOLD=80
DISK_CRIT_THRESHOLD=90
MEMORY_WARN_THRESHOLD=80
CPU_WARN_THRESHOLD=80

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

log "=========================================="
log "HomeSec Health Check"
log "=========================================="

################################################################################
# 1. Check Disk Space
################################################################################
log "Checking disk space..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')

if [ "$DISK_USAGE" -ge "$DISK_CRIT_THRESHOLD" ]; then
    log_error "Disk usage critical: ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -ge "$DISK_WARN_THRESHOLD" ]; then
    log_warning "Disk usage high: ${DISK_USAGE}%"
else
    log_ok "Disk usage healthy: ${DISK_USAGE}%"
fi

# Check backup disk
if [ -d "/mnt/storage" ]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    BACKUP_USAGE=$(df -h /mnt/storage | tail -1 | awk '{print $5}' | tr -d '%')

    if [ "$BACKUP_USAGE" -ge "$DISK_CRIT_THRESHOLD" ]; then
        log_error "Backup disk usage critical: ${BACKUP_USAGE}%"
    elif [ "$BACKUP_USAGE" -ge "$DISK_WARN_THRESHOLD" ]; then
        log_warning "Backup disk usage high: ${BACKUP_USAGE}%"
    else
        log_ok "Backup disk usage healthy: ${BACKUP_USAGE}%"
    fi
fi

################################################################################
# 2. Check Memory Usage
################################################################################
log "Checking memory usage..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

if [ "$MEMORY_USAGE" -ge "$MEMORY_WARN_THRESHOLD" ]; then
    log_warning "Memory usage high: ${MEMORY_USAGE}%"
else
    log_ok "Memory usage healthy: ${MEMORY_USAGE}%"
fi

################################################################################
# 3. Check CPU Load
################################################################################
log "Checking CPU load..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
CPU_COUNT=$(nproc)

# Check if load average is greater than CPU count
if (( $(echo "$LOAD_AVG > $CPU_COUNT" | bc -l) )); then
    log_warning "CPU load high: ${LOAD_AVG} (${CPU_COUNT} CPUs)"
else
    log_ok "CPU load healthy: ${LOAD_AVG} (${CPU_COUNT} CPUs)"
fi

################################################################################
# 4. Check Services
################################################################################
log "Checking services..."

# Elasticsearch
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if systemctl is-active --quiet elasticsearch || podman ps | grep -q elasticsearch; then
    if curl -s -f http://localhost:9200 > /dev/null 2>&1; then
        log_ok "Elasticsearch is running and responsive"
    else
        log_error "Elasticsearch is running but not responsive"
    fi
else
    log_error "Elasticsearch is not running"
fi

# Kibana
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if systemctl is-active --quiet kibana || podman ps | grep -q kibana; then
    log_ok "Kibana is running"
else
    log_error "Kibana is not running"
fi

# BIND DNS
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if systemctl is-active --quiet named; then
    log_ok "BIND DNS is running"
else
    log_warning "BIND DNS is not running"
fi

# Samba
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if systemctl is-active --quiet smb; then
    log_ok "Samba is running"
else
    log_warning "Samba is not running"
fi

# Filebeat
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if systemctl is-active --quiet filebeat; then
    log_ok "Filebeat is running"
else
    log_warning "Filebeat is not running"
fi

# Metricbeat
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if systemctl is-active --quiet metricbeat; then
    log_ok "Metricbeat is running"
else
    log_warning "Metricbeat is not running"
fi

################################################################################
# 5. Check Network Connectivity
################################################################################
log "Checking network connectivity..."

# Internet connectivity
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if ping -c 2 -W 3 8.8.8.8 > /dev/null 2>&1; then
    log_ok "Internet connectivity OK"
else
    log_error "No internet connectivity"
fi

# Rock Pi 4 SE (IDS)
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if ping -c 1 -W 2 192.168.20.20 > /dev/null 2>&1; then
    log_ok "Rock Pi 4 SE is reachable"
else
    log_warning "Rock Pi 4 SE is not reachable"
fi

# OpenWrt Router
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if ping -c 1 -W 2 192.168.20.1 > /dev/null 2>&1; then
    log_ok "OpenWrt router is reachable"
else
    log_error "OpenWrt router is not reachable"
fi

################################################################################
# 6. Check RAID Status
################################################################################
if [ -f /proc/mdstat ]; then
    log "Checking RAID status..."
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if grep -q "_" /proc/mdstat; then
        log_error "RAID array degraded!"
        cat /proc/mdstat | tee -a "$LOG_FILE"
    else
        if grep -q "active" /proc/mdstat; then
            log_ok "RAID array healthy"
        else
            log_warning "RAID status unknown"
        fi
    fi
fi

################################################################################
# 7. Check for Errors in Logs
################################################################################
log "Checking for recent errors..."
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

ERROR_COUNT=$(journalctl --since "1 hour ago" --priority err | wc -l)

if [ "$ERROR_COUNT" -gt 10 ]; then
    log_warning "Found ${ERROR_COUNT} errors in logs (last hour)"
elif [ "$ERROR_COUNT" -gt 0 ]; then
    log_ok "${ERROR_COUNT} errors found (acceptable)"
else
    log_ok "No errors found in logs"
fi

################################################################################
# 8. Summary
################################################################################
log "=========================================="
log "Health Check Summary:"
log "  Total checks: ${TOTAL_CHECKS}"
log "  Passed: ${PASSED_CHECKS}"
log "  Warnings: ${WARNING_CHECKS}"
log "  Failed: ${FAILED_CHECKS}"
log "=========================================="

# Exit code based on results
if [ $FAILED_CHECKS -gt 0 ]; then
    log "Health check FAILED"
    # Uncomment to send email alert
    # echo "HomeSec health check found ${FAILED_CHECKS} critical issue(s). Check ${LOG_FILE} for details." | \
    #     mail -s "HomeSec Health Check FAILED" "$ALERT_EMAIL"
    exit 1
elif [ $WARNING_CHECKS -gt 0 ]; then
    log "Health check completed with WARNINGS"
    exit 2
else
    log "Health check PASSED"
    exit 0
fi
