# Maintenance Scripts

## Overview

Automated maintenance scripts for HomeSec infrastructure to keep systems running smoothly and securely.

## Scripts

### 1. update-systems.sh
Updates all components (server, Rock Pis, OpenWrt router)

**Schedule**: Weekly (Sunday 3 AM)
**Duration**: ~30-60 minutes

### 2. clean-logs.sh
Rotates and archives old logs, frees disk space

**Schedule**: Weekly (Sunday 4 AM)
**Duration**: ~5-10 minutes

### 3. update-suricata-rules.sh
Updates Suricata detection rules on IDS/IPS

**Schedule**: Daily (2 AM)
**Duration**: ~5 minutes

### 4. check-health.sh
Health check for all components, sends alerts if issues found

**Schedule**: Hourly
**Duration**: ~2 minutes

### 5. optimize-elasticsearch.sh
Optimizes Elasticsearch indices, manages retention

**Schedule**: Weekly (Sunday 5 AM)
**Duration**: ~10-30 minutes

### 6. security-audit.sh
Security audit of firewall rules, open ports, and configurations

**Schedule**: Weekly (Monday 3 AM)
**Duration**: ~5 minutes

## Installation

### Copy Scripts

```bash
# Copy to /usr/local/bin
sudo cp update-systems.sh /usr/local/bin/
sudo cp clean-logs.sh /usr/local/bin/
sudo cp update-suricata-rules.sh /usr/local/bin/
sudo cp check-health.sh /usr/local/bin/
sudo cp optimize-elasticsearch.sh /usr/local/bin/
sudo cp security-audit.sh /usr/local/bin/

# Make executable
sudo chmod +x /usr/local/bin/update-systems.sh
sudo chmod +x /usr/local/bin/clean-logs.sh
sudo chmod +x /usr/local/bin/update-suricata-rules.sh
sudo chmod +x /usr/local/bin/check-health.sh
sudo chmod +x /usr/local/bin/optimize-elasticsearch.sh
sudo chmod +x /usr/local/bin/security-audit.sh
```

### Set Up Cron Jobs

```bash
# Edit root crontab
sudo crontab -e

# Add maintenance jobs:

# Daily Suricata rule updates (2 AM)
0 2 * * * /usr/local/bin/update-suricata-rules.sh >> /var/log/maintenance.log 2>&1

# Hourly health check
0 * * * * /usr/local/bin/check-health.sh >> /var/log/health-check.log 2>&1

# Weekly system updates (Sunday 3 AM)
0 3 * * 0 /usr/local/bin/update-systems.sh >> /var/log/maintenance.log 2>&1

# Weekly log cleanup (Sunday 4 AM)
0 4 * * 0 /usr/local/bin/clean-logs.sh >> /var/log/maintenance.log 2>&1

# Weekly Elasticsearch optimization (Sunday 5 AM)
0 5 * * 0 /usr/local/bin/optimize-elasticsearch.sh >> /var/log/maintenance.log 2>&1

# Weekly security audit (Monday 3 AM)
0 3 * * 1 /usr/local/bin/security-audit.sh >> /var/log/security-audit.log 2>&1
```

## Manual Execution

All scripts can be run manually:

```bash
# Update all systems
sudo /usr/local/bin/update-systems.sh

# Clean logs
sudo /usr/local/bin/clean-logs.sh

# Update Suricata rules
sudo /usr/local/bin/update-suricata-rules.sh

# Run health check
sudo /usr/local/bin/check-health.sh

# Optimize Elasticsearch
sudo /usr/local/bin/optimize-elasticsearch.sh

# Run security audit
sudo /usr/local/bin/security-audit.sh
```

## Script Details

### update-systems.sh

Updates packages on:
- CentOS server
- Rock Pi 4 SE (IDS)
- Rock Pi E (IPS)
- OpenWrt router

**Options**:
- `--server-only`: Update server only
- `--rockpis-only`: Update Rock Pis only
- `--router-only`: Update router only
- `--no-reboot`: Skip reboot even if required

### clean-logs.sh

Cleans up:
- Old Suricata logs (>30 days)
- Old system logs (>60 days)
- Rotated archives (>90 days)
- Temporary files

**Options**:
- `--dry-run`: Show what would be deleted
- `--keep-days N`: Change retention to N days

### update-suricata-rules.sh

Updates detection rules on:
- Rock Pi 4 SE (IDS)
- Rock Pi E (IPS)

Sources:
- Emerging Threats Open
- OISF Traffic ID
- Custom HomeSec rules

**Options**:
- `--ids-only`: Update IDS only
- `--ips-only`: Update IPS only
- `--test-only`: Test rules without applying

### check-health.sh

Checks:
- Service status (Elasticsearch, Kibana, Suricata, BIND, Samba)
- Disk space (warn at 80%, alert at 90%)
- Memory usage (warn at 80%)
- CPU load
- Network connectivity
- RAID status
- Log for errors

**Options**:
- `--verbose`: Show detailed output
- `--email`: Send email if issues found
- `--slack`: Send Slack notification if issues found

### optimize-elasticsearch.sh

Performs:
- Force merge old indices
- Delete indices outside retention policy
- Optimize index settings
- Clear cache
- Snapshot repository cleanup

**Options**:
- `--force-merge-only`: Only force merge
- `--cleanup-only`: Only delete old indices
- `--dry-run`: Show what would be done

### security-audit.sh

Audits:
- Open ports
- Firewall rules
- Failed login attempts
- Unusual network connections
- File integrity (key configs)
- User accounts
- SSH keys
- Honeypot isolation

**Options**:
- `--full`: Full audit (slower)
- `--quick`: Quick audit (essential checks only)
- `--report FILE`: Save report to file

## Monitoring Maintenance Tasks

### View Logs

```bash
# Maintenance log
sudo tail -f /var/log/maintenance.log

# Health check log
sudo tail -f /var/log/health-check.log

# Security audit log
sudo tail -f /var/log/security-audit.log

# Check for errors
sudo grep -i error /var/log/maintenance.log
```

### Monitor via Kibana

Create dashboard to monitor:
- Maintenance task execution
- Health check results
- Security audit findings

Query examples:
```
# Maintenance errors
log_type:maintenance AND level:error

# Health check failures
log_type:health_check AND status:failed

# Security audit warnings
log_type:security_audit AND severity:(warning OR critical)
```

## Alerting

### Email Alerts

Configure email in scripts:
```bash
# In each script
ALERT_EMAIL="admin@homesec.local"
SMTP_SERVER="smtp.example.com"
```

### Slack Alerts

Configure Slack webhook:
```bash
# In each script
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

## Troubleshooting

### Script Fails to Run

```bash
# Check script is executable
ls -la /usr/local/bin/update-systems.sh

# Check for syntax errors
bash -n /usr/local/bin/update-systems.sh

# Run with verbose output
bash -x /usr/local/bin/update-systems.sh
```

### Cron Job Not Running

```bash
# Check cron service
sudo systemctl status crond

# Check crontab
sudo crontab -l

# Check cron logs
sudo journalctl -u crond | tail -50

# Test cron job manually
sudo /usr/local/bin/check-health.sh
```

### SSH Connection Issues (Rock Pis/Router)

```bash
# Test SSH connectivity
ssh -o ConnectTimeout=5 root@192.168.20.20 echo "OK"

# Check SSH keys
ls -la ~/.ssh/

# Add SSH key if needed
ssh-copy-id root@192.168.20.20
```

## Maintenance Schedule

### Daily
- 02:00 - Update Suricata rules
- Hourly - Health checks

### Weekly
- Sunday 03:00 - System updates
- Sunday 04:00 - Log cleanup
- Sunday 05:00 - Elasticsearch optimization
- Monday 03:00 - Security audit

### Monthly
- 1st of month - Full security audit
- 15th of month - Verify backups
- Last day - Review logs and metrics

## Related Documentation

- [Backup System](../../server/backup/README.md)
- [Monitoring](../../server/monitoring/README.md)
- [Architecture](../../docs/architecture.md)
- [Troubleshooting](../../docs/troubleshooting.md)
