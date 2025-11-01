# Kibana Dashboards

## Overview

This directory contains Kibana dashboard templates and visualization configurations for HomeSec monitoring.

**Access**: https://192.168.20.10:443 (via VPN)
**Data Sources**: Elasticsearch indices (homesec-*)

## Dashboard Inventory

### 1. Security Overview Dashboard
**File**: `kibana/security-overview.ndjson`
**Purpose**: High-level security monitoring
**Visualizations**:
- Alert count over time
- Alert severity distribution
- Top alert signatures
- Top source IPs
- Top destination IPs
- Geographic map of attack sources
- Alert trends (24h, 7d, 30d)

### 2. Honeypot Activity Dashboard
**File**: `kibana/honeypot-activity.ndjson`
**Purpose**: Monitor attacks on T-Pot honeypot
**Visualizations**:
- Attacks per protocol
- Attacker source countries (GeoIP)
- Attack timeline
- Top attacked services
- Brute force attempts
- Malware samples collected
- Attack patterns

### 3. Network Traffic Dashboard
**File**: `kibana/network-traffic.ndjson`
**Purpose**: Network traffic analysis
**Visualizations**:
- Traffic volume by VLAN
- Protocol distribution
- Top talkers
- Bandwidth usage over time
- Connection states
- Port usage statistics

### 4. DNS Analysis Dashboard
**File**: `kibana/dns-analysis.ndjson`
**Purpose**: DNS query monitoring
**Visualizations**:
- Query volume over time
- Top queried domains
- Query types distribution
- Suspicious domain detection
- DNS tunneling indicators
- Queries from honeypot

### 5. System Health Dashboard
**File**: `kibana/system-health.ndjson`
**Purpose**: Infrastructure monitoring
**Visualizations**:
- CPU usage (all components)
- Memory usage
- Disk usage
- Network I/O
- Service status
- Component uptime

### 6. IDS/IPS Performance Dashboard
**File**: `kibana/ids-ips-performance.ndjson`
**Purpose**: Suricata performance monitoring
**Visualizations**:
- Packet processing rate
- Dropped packets
- Flow cache usage
- Memory usage
- CPU usage per worker thread
- Rule performance

## Installation

### 1. Access Kibana

```bash
# Via VPN
https://192.168.20.10:443
```

### 2. Import Dashboards

#### Via UI:
1. Navigate to **Management** → **Stack Management** → **Saved Objects**
2. Click **Import**
3. Select dashboard `.ndjson` file from `kibana/` directory
4. Click **Import**
5. Resolve any conflicts (choose "Overwrite" if updating existing dashboard)

#### Via API:
```bash
# Import dashboard via API
curl -X POST "http://192.168.20.10:9200/api/saved_objects/_import" \
  -H "kbn-xsrf: true" \
  --form file=@kibana/security-overview.ndjson
```

### 3. Configure Index Patterns

Before importing dashboards, ensure index patterns exist:

```bash
# Create index patterns via Kibana UI:
# Management → Stack Management → Index Patterns → Create index pattern

# Required index patterns:
# - homesec-ids-*      (IDS data from Rock Pi 4 SE)
# - homesec-ips-*      (IPS data from Rock Pi E)
# - homesec-metrics-*  (System metrics)
# - homesec-server-*   (Server logs)
# - homesec-firewall-* (Firewall logs)
# - homesec-dns-*      (DNS logs)
```

### 4. Set Default Dashboard

1. Go to **Management** → **Advanced Settings**
2. Set `defaultRoute` to `/app/dashboards#/view/<dashboard-id>`
3. Save

## Dashboard Customization

### Modify Existing Dashboard

1. Open dashboard in Kibana
2. Click **Edit**
3. Add/remove/modify visualizations
4. Click **Save**
5. Export updated dashboard: **Share** → **Export**

### Create Custom Dashboard

1. Go to **Dashboard** → **Create dashboard**
2. Click **Add** → **Create visualization** or **Add from library**
3. Configure visualizations
4. **Save** dashboard

### Export Dashboard

1. Go to **Management** → **Stack Management** → **Saved Objects**
2. Select dashboards to export
3. Click **Export**
4. Save `.ndjson` file to `kibana/` directory

## Common Queries

### Security Monitoring

```
# High severity alerts
_index:homesec-ids-* AND event_type:alert AND alert.severity:[1 TO 2]

# Honeypot attacks
(dest_ip:192.168.99.10 OR src_ip:192.168.99.10) AND event_type:alert

# SSH brute force
alert.signature:*brute*force* AND dest_port:22

# DNS tunneling indicators
event_type:dns AND dns.query_length:>50

# Malware downloads
event_type:fileinfo AND fileinfo.size:>0
```

### Network Analysis

```
# Top bandwidth consumers
src_ip:* | stats sum(bytes) by src_ip | sort sum(bytes) desc | head 10

# Traffic by VLAN
src_ip:192.168.10.* OR src_ip:192.168.20.* OR src_ip:192.168.30.*

# External connections
NOT (dest_ip:192.168.* OR dest_ip:10.* OR dest_ip:172.16.*)
```

### System Health

```
# High CPU usage
system.cpu.user.pct:>0.8

# Low disk space
system.filesystem.available:<10000000000

# Service down
metricset.name:status AND service.status:down
```

## Alerting

### Create Alert

1. Go to **Management** → **Stack Management** → **Alerts and Insights** → **Rules**
2. Click **Create rule**
3. Select rule type (e.g., "Elasticsearch query")
4. Configure:
   - **Index**: homesec-ids-*
   - **Query**: `event_type:alert AND alert.severity:1`
   - **Threshold**: Count > 10 in 5 minutes
   - **Action**: Email, Slack, webhook, etc.
5. Save rule

### Example Alerts

#### High Severity Alert
- **Condition**: More than 5 severity 1 alerts in 5 minutes
- **Action**: Email admin
- **Query**: `_index:homesec-ids-* AND alert.severity:1`

#### Honeypot Attack Spike
- **Condition**: More than 100 honeypot alerts in 1 hour
- **Action**: Email + Slack notification
- **Query**: `dest_ip:192.168.99.10 AND event_type:alert`

#### Disk Space Low
- **Condition**: Available disk space < 10%
- **Action**: Email admin
- **Query**: `system.filesystem.used.pct:>90`

#### Service Down
- **Condition**: Service status not "running"
- **Action**: Email + push notification
- **Query**: `service.status:NOT(running)`

## Dashboard Templates

### Template Structure

```json
{
  "type": "dashboard",
  "id": "security-overview",
  "attributes": {
    "title": "Security Overview",
    "description": "High-level security monitoring dashboard",
    "panelsJSON": "[...]",
    "optionsJSON": "{...}",
    "timeRestore": true,
    "refreshInterval": {
      "pause": false,
      "value": 60000
    }
  }
}
```

### Visualization Types

- **Line Chart**: Time-series data (alerts over time, CPU usage)
- **Bar Chart**: Comparisons (alerts by severity, traffic by VLAN)
- **Pie Chart**: Distribution (protocol distribution, alert types)
- **Data Table**: Detailed lists (top IPs, top domains)
- **Metric**: Single value (total alerts, system uptime)
- **Map**: Geographic data (attack sources with GeoIP)
- **Heat Map**: Correlation (time of day vs attack volume)
- **Gauge**: Current status (disk usage, memory usage)

## Best Practices

### Dashboard Design

1. **Keep it focused**: One dashboard per purpose
2. **Use time filters**: Allow dynamic time range selection
3. **Group related visualizations**: Use panels/sections
4. **Add descriptions**: Help users understand what they're seeing
5. **Optimize queries**: Use filters to reduce data volume
6. **Set appropriate refresh intervals**: Balance between real-time and performance

### Performance

- Limit time range for heavy queries
- Use index patterns efficiently
- Cache frequently used visualizations
- Aggregate data when possible
- Avoid wildcard queries on high-cardinality fields

### Security

- Use Kibana Spaces to separate dashboards by team/function
- Set up role-based access control (RBAC)
- Limit access to sensitive data
- Audit dashboard access

## Maintenance

### Weekly

- Review dashboard performance (slow queries)
- Update visualizations based on new data patterns
- Export updated dashboards to `kibana/` directory

### Monthly

- Archive old dashboards
- Clean up unused visualizations
- Review alert rules and adjust thresholds
- Document any custom dashboards

## Troubleshooting

### Dashboard Not Loading

```bash
# Check Kibana is running
curl http://192.168.20.10:443/api/status

# Check Elasticsearch connection
curl http://192.168.20.10:9200/_cluster/health

# Check Kibana logs
podman logs kibana | tail -50
```

### Visualization Shows No Data

- Verify index pattern matches data
- Check time range
- Verify field names in visualization config
- Check Elasticsearch has data: `curl "http://localhost:9200/homesec-ids-*/_count"`

### Import Fails

- Check .ndjson file format
- Ensure all dependencies exist (index patterns, visualizations)
- Check Kibana version compatibility
- Try importing components individually

## Related Documentation

- [ELK Stack Setup](../server/elk-stack/README.md)
- [Monitoring Configuration](../server/monitoring/README.md)
- [Architecture](../docs/architecture.md)
- Kibana docs: https://www.elastic.co/guide/en/kibana/current/index.html
