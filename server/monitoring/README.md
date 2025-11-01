# Monitoring & Data Collection

## Overview

This directory contains configuration files for Filebeat and Metricbeat agents that collect logs and metrics from various HomeSec components and send them to the ELK Stack.

## Components

### Filebeat
- **Purpose**: Collects and ships log files
- **Sources**: Suricata logs, system logs, application logs
- **Destination**: Elasticsearch (192.168.20.10:9200)

### Metricbeat
- **Purpose**: Collects and ships system metrics
- **Sources**: CPU, memory, disk, network, process stats
- **Destination**: Elasticsearch (192.168.20.10:9200)

## Deployment Map

| Component | Filebeat | Metricbeat | Logs Collected |
|-----------|----------|------------|----------------|
| **CentOS Server** | ✓ | ✓ | System logs, Docker logs, Elasticsearch logs |
| **Rock Pi 4 SE (IDS)** | ✓ | ✓ | Suricata EVE JSON, system metrics |
| **Rock Pi E (IPS)** | ✓ | ✓ | Suricata EVE JSON, system metrics |
| **OpenWrt Router** | ✓ | ✗ | Firewall logs, system logs, WireGuard logs |
| **HP Switch** | ✗ | ✗ | sFlow to Rock Pi 4 SE (alternative) |

## Installation

### On CentOS Server

```bash
# Install Filebeat and Metricbeat
sudo yum install -y filebeat metricbeat

# Copy configuration files
sudo cp filebeat-server.yml /etc/filebeat/filebeat.yml
sudo cp metricbeat-server.yml /etc/metricbeat/metricbeat.yml

# Enable modules
sudo filebeat modules enable system elasticsearch kibana

# Test configuration
sudo filebeat test config
sudo filebeat test output
sudo metricbeat test config
sudo metricbeat test output

# Enable and start services
sudo systemctl enable filebeat metricbeat
sudo systemctl start filebeat metricbeat

# Verify
sudo systemctl status filebeat metricbeat
```

### On Rock Pi Devices (Already Covered)

See component-specific READMEs:
- [Rock Pi 4 SE IDS](../../ids-ips/rockpi4-ids/README.md)
- [Rock Pi E IPS](../../ids-ips/rockpi-e-ips/README.md)

### On OpenWrt Router

```bash
# SSH to router
ssh root@192.168.20.1

# Install logread package if not present
opkg update
opkg install logd

# Configure remote syslog to Rock Pi 4 SE
uci set system.@system[0].log_ip='192.168.20.20'
uci set system.@system[0].log_port='514'
uci set system.@system[0].log_proto='udp'
uci commit system
/etc/init.d/log restart

# Alternatively, install Filebeat for OpenWrt (if available)
# See filebeat-openwrt.conf for configuration
```

## Configuration Files

### filebeat-server.yml
Filebeat configuration for CentOS server. Collects:
- System logs (/var/log/messages, /var/log/secure)
- Elasticsearch logs
- Kibana logs
- Podman/Docker container logs

### metricbeat-server.yml
Metricbeat configuration for CentOS server. Collects:
- System metrics (CPU, memory, disk, network)
- Elasticsearch metrics
- Kibana metrics
- Docker/Podman container metrics

### filebeat-openwrt.conf
Filebeat configuration template for OpenWrt router. Collects:
- Firewall logs
- DHCP logs
- WireGuard VPN logs
- System logs

## Index Naming Convention

| Data Source | Index Pattern | Example |
|-------------|---------------|---------|
| Suricata IDS (Rock Pi 4 SE) | `homesec-ids-*` | `homesec-ids-2024.01.15` |
| Suricata IPS (Rock Pi E) | `homesec-ips-*` | `homesec-ips-2024.01.15` |
| System metrics | `homesec-metrics-*` | `homesec-metrics-2024.01.15` |
| Server logs | `homesec-server-*` | `homesec-server-2024.01.15` |
| Firewall logs | `homesec-firewall-*` | `homesec-firewall-2024.01.15` |

## Data Retention

Configure Index Lifecycle Management (ILM) in Kibana:

```bash
# Access Kibana
https://192.168.20.10:443

# Navigate to: Management → Stack Management → Index Lifecycle Policies

# Create policy "homesec-ilm-policy":
# - Hot phase: 0-7 days (indexing and querying)
# - Warm phase: 7-30 days (compressed, read-only)
# - Delete phase: After 30 days
```

Apply to all `homesec-*` indices.

## Monitoring Beats

### Check Filebeat Status

```bash
# On any host
sudo systemctl status filebeat

# View logs
sudo journalctl -u filebeat -n 50 -f

# Check what's being harvested
sudo filebeat export config | grep path

# Test output connection
sudo filebeat test output
```

### Check Metricbeat Status

```bash
# On any host
sudo systemctl status metricbeat

# View logs
sudo journalctl -u metricbeat -n 50 -f

# Test output
sudo metricbeat test output
```

### Verify Data in Elasticsearch

```bash
# Check indices
curl -X GET "http://192.168.20.10:9200/_cat/indices/homesec-*?v&s=index"

# Count documents in IDS index
curl -X GET "http://192.168.20.10:9200/homesec-ids-*/_count?pretty"

# Sample recent alerts
curl -X GET "http://192.168.20.10:9200/homesec-ids-*/_search?size=5&sort=@timestamp:desc&pretty"

# Check metrics data
curl -X GET "http://192.168.20.10:9200/homesec-metrics-*/_count?pretty"
```

## Troubleshooting

### No Data in Elasticsearch

```bash
# 1. Check Filebeat/Metricbeat are running
sudo systemctl status filebeat metricbeat

# 2. Check configuration
sudo filebeat test config
sudo metricbeat test config

# 3. Test connectivity to Elasticsearch
curl http://192.168.20.10:9200

# 4. Test output
sudo filebeat test output
sudo metricbeat test output

# 5. Check logs for errors
sudo journalctl -u filebeat -n 100 | grep -i error
sudo journalctl -u metricbeat -n 100 | grep -i error

# 6. Verify firewall allows traffic
sudo firewall-cmd --list-all
```

### Filebeat Registry Issues

```bash
# Check registry
sudo cat /var/lib/filebeat/registry/filebeat/log.json | jq .

# If stuck, reset registry (CAUTION: may cause duplicate events)
sudo systemctl stop filebeat
sudo rm -rf /var/lib/filebeat/registry
sudo systemctl start filebeat
```

### High Memory Usage

```bash
# Check queue settings in filebeat.yml
queue.mem.events: 4096  # Reduce if needed
queue.mem.flush.min_events: 2048

# Restart Filebeat
sudo systemctl restart filebeat
```

### Missing Fields in Elasticsearch

```bash
# Reload Filebeat index template
sudo filebeat setup --index-management

# Force reload (if indices already exist)
sudo filebeat setup --index-management -E 'setup.template.overwrite=true'
```

## Custom Parsing

### Add Custom Log Parsing

For custom application logs, add parsing rules:

```yaml
# In filebeat.yml
processors:
  - dissect:
      tokenizer: "%{timestamp} %{level} %{message}"
      field: "message"
      target_prefix: "custom"
```

### Add GeoIP Enrichment

```yaml
# In filebeat.yml
processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
  - add_locale: ~
```

## Performance Tuning

### Filebeat Optimization

```yaml
# Increase bulk size for better throughput
output.elasticsearch:
  bulk_max_size: 2048

# Adjust worker count
output.elasticsearch:
  worker: 2

# Increase queue size
queue.mem:
  events: 8192
  flush.min_events: 4096
```

### Metricbeat Optimization

```yaml
# Adjust collection period
metricsets:
  period: 30s  # Increase from 10s to reduce load
```

## Security

### Enable TLS (Optional)

If Elasticsearch has TLS enabled:

```yaml
output.elasticsearch:
  hosts: ["192.168.20.10:9200"]
  protocol: "https"
  ssl.certificate_authorities: ["/etc/pki/tls/certs/ca.crt"]
  ssl.verification_mode: "certificate"
```

### Enable Authentication (Optional)

```yaml
output.elasticsearch:
  hosts: ["192.168.20.10:9200"]
  username: "elastic"
  password: "${ES_PASSWORD}"
```

Store password in environment or keystore:
```bash
sudo filebeat keystore create
sudo filebeat keystore add ES_PASSWORD
```

## Backup

```bash
# Backup Beat configurations
sudo tar -czf /tmp/beats-config-$(date +%Y%m%d).tar.gz \
    /etc/filebeat/ \
    /etc/metricbeat/

# Copy to server
scp /tmp/beats-config-*.tar.gz user@192.168.20.10:/mnt/raid/backups/
```

## Maintenance

### Weekly

```bash
# Update Beats
sudo yum update filebeat metricbeat -y

# Restart services
sudo systemctl restart filebeat metricbeat

# Verify data flow
curl "http://192.168.20.10:9200/_cat/indices/homesec-*?v"
```

### Monthly

```bash
# Review index sizes
curl "http://192.168.20.10:9200/_cat/indices/homesec-*?v&h=index,store.size&s=store.size:desc"

# Check for old indices (outside retention period)
# Delete manually if ILM not configured

# Review Filebeat harvester logs for issues
sudo journalctl -u filebeat --since "1 month ago" | grep -i error
```

## Related Documentation

- [ELK Stack Setup](../elk-stack/README.md)
- [Rock Pi 4 SE IDS](../../ids-ips/rockpi4-ids/README.md)
- [Architecture](../../docs/architecture.md)
- [Filebeat Documentation](https://www.elastic.co/guide/en/beats/filebeat/current/index.html)
- [Metricbeat Documentation](https://www.elastic.co/guide/en/beats/metricbeat/current/index.html)

## Example Queries

### Kibana Discover Queries

```
# All Suricata alerts from IDS
_index:homesec-ids-* AND event_type:alert

# High severity alerts
_index:homesec-ids-* AND event_type:alert AND alert.severity:[1 TO 2]

# Server CPU usage >80%
_index:homesec-metrics-* AND system.cpu.user.pct:>0.8

# Firewall blocks
_index:homesec-firewall-* AND action:DROP
```

These configurations ensure comprehensive monitoring and logging across all HomeSec components.
