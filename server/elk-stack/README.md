# ELK Stack - Elasticsearch, Kibana, Logstash

## Overview

The ELK Stack is the central logging and visualization platform for HomeSec.

**Components**:
- **Elasticsearch**: Search and analytics engine, stores all logs
- **Kibana**: Visualization and dashboard UI
- **Logstash**: Log processing and enrichment (optional)

**Deployment**: Podman containers on CentOS server

## Quick Start

```bash
# Navigate to elk-stack directory
cd /opt/homesec/server/elk-stack

# Start all services
podman-compose up -d

# Check status
podman-compose ps

# View logs
podman-compose logs -f

# Access Kibana
# Open browser: https://192.168.20.10:443
```

## Installation

### 1. Prerequisites

```bash
# Install Podman
sudo dnf install -y podman podman-compose

# Create directories
sudo mkdir -p /opt/homesec/server/elk-stack/{elasticsearch,kibana,logstash}/{config,data}

# Set permissions
sudo chown -R $USER:$USER /opt/homesec
```

### 2. System Tuning

Elasticsearch requires specific system settings:

```bash
# Increase vm.max_map_count
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Disable swap (optional but recommended)
sudo swapoff -a

# Or limit swappiness
echo "vm.swappiness=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 3. Copy Configuration Files

```bash
cd /opt/homesec/server/elk-stack

# Copy docker-compose.yml
cp /path/to/homesec-project/server/elk-stack/docker-compose.yml .

# Create config files (see below)
```

### 4. Create Configuration Files

#### Elasticsearch Config

Create `elasticsearch/config/elasticsearch.yml`:

```yaml
cluster.name: "homesec-cluster"
network.host: 0.0.0.0

# Disable security for internal network
xpack.security.enabled: false

# Paths
path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs

# Discovery
discovery.type: single-node

# Index settings
action.auto_create_index: true
```

#### Kibana Config

Create `kibana/config/kibana.yml`:

```yaml
server.name: "HomeSec-Kibana"
server.host: "0.0.0.0"
server.port: 5601

elasticsearch.hosts: ["http://elasticsearch:9200"]

# Monitoring
monitoring.ui.container.elasticsearch.enabled: true

# Disable security warnings (if xpack.security disabled)
xpack.security.enabled: false
```

#### Logstash Config (Optional)

Create `logstash/config/logstash.yml`:

```yaml
http.host: "0.0.0.0"
xpack.monitoring.elasticsearch.hosts: ["http://elasticsearch:9200"]
```

Create `logstash/pipeline/homesec.conf`:

```
input {
  beats {
    port => 5044
  }
}

filter {
  # Parse Suricata EVE JSON
  if [event][module] == "suricata" {
    json {
      source => "message"
    }

    # Add GeoIP for external IPs
    if [src_ip] and [src_ip] !~ /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/ {
      geoip {
        source => "src_ip"
        target => "geoip_src"
      }
    }

    if [dest_ip] and [dest_ip] !~ /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/ {
      geoip {
        source => "dest_ip"
        target => "geoip_dest"
      }
    }
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "homesec-%{[event][module]}-%{+YYYY.MM.dd}"
  }
}
```

### 5. Start Services

```bash
# Start all containers
podman-compose up -d

# Wait for Elasticsearch to start (takes ~60 seconds)
sleep 60

# Verify Elasticsearch
curl http://192.168.20.10:9200

# Verify Kibana (takes ~30 seconds after Elasticsearch)
curl http://192.168.20.10:443/api/status
```

### 6. Configure Firewall

```bash
# Allow access from VPN and Infrastructure VLAN
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.20.0/24" port port="9200" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.20.0/24" port port="443" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.100.0/24" port port="443" protocol="tcp" accept'
sudo firewall-cmd --reload
```

## Usage

### Access Kibana

1. Connect via VPN
2. Open browser: https://192.168.20.10:443
3. First time: Wait for Kibana to initialize (~2 minutes)

### Create Index Patterns

In Kibana:

1. Navigate to **Stack Management → Index Patterns**
2. Click **Create index pattern**
3. Create patterns:
   - `homesec-ips-*` (Rock Pi E IPS alerts)
   - `homesec-ids-*` (Rock Pi 4 SE IDS alerts)
   - `homesec-tpot-*` (T-Pot honeypot data)
   - `metricbeat-*` (System metrics)
   - `filebeat-*` (General logs)

4. Set time field: `@timestamp`

### Import Dashboards

```bash
# Import pre-configured dashboards
# See: dashboards/kibana/ directory
```

## Data Retention

### Configure Index Lifecycle Policy (ILM)

In Kibana → Stack Management → Index Lifecycle Policies:

```json
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "50GB",
            "max_age": "7d"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

**Retention**:
- Hot data: 0-7 days (full indexing, fast queries)
- Warm data: 7-30 days (read-only, compressed)
- Delete: After 30 days

Adjust based on disk space and requirements.

## Backup

### Manual Snapshot

```bash
# Register snapshot repository
curl -X PUT "http://192.168.20.10:9200/_snapshot/homesec_backup" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/mnt/raid/backups/elasticsearch"
  }
}'

# Create snapshot
curl -X PUT "http://192.168.20.10:9200/_snapshot/homesec_backup/snapshot_$(date +%Y%m%d)?wait_for_completion=true"

# List snapshots
curl "http://192.168.20.10:9200/_snapshot/homesec_backup/_all"
```

### Automated Backup Script

Create `/opt/homesec/scripts/backup-elasticsearch.sh`:

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
SNAPSHOT_NAME="snapshot_${DATE}"

# Create snapshot
curl -X PUT "http://192.168.20.10:9200/_snapshot/homesec_backup/${SNAPSHOT_NAME}?wait_for_completion=false"

echo "Elasticsearch snapshot initiated: ${SNAPSHOT_NAME}"
```

Add to crontab:
```bash
# Daily at 2 AM
0 2 * * * /opt/homesec/scripts/backup-elasticsearch.sh
```

## Monitoring

### Check Cluster Health

```bash
# Cluster health
curl http://192.168.20.10:9200/_cluster/health?pretty

# Node stats
curl http://192.168.20.10:9200/_nodes/stats?pretty

# Index stats
curl http://192.168.20.10:9200/_cat/indices?v
```

### Monitor Disk Usage

```bash
# Check Elasticsearch data directory
du -sh /opt/homesec/server/elk-stack/elasticsearch/data

# Check indices size
curl http://192.168.20.10:9200/_cat/indices?v&h=index,store.size&s=store.size:desc
```

### Monitor Container Resources

```bash
# Container stats
podman stats

# Specific container
podman stats elasticsearch
```

## Troubleshooting

### Elasticsearch Won't Start

```bash
# Check logs
podman logs elasticsearch

# Common issues:
# 1. vm.max_map_count too low
sudo sysctl -w vm.max_map_count=262144

# 2. Insufficient memory
# Reduce heap size in docker-compose.yml:
# ES_JAVA_OPTS=-Xms2g -Xmx2g

# 3. Port already in use
sudo netstat -tulpn | grep 9200
```

### Kibana Not Accessible

```bash
# Check if Elasticsearch is running
curl http://192.168.20.10:9200

# Check Kibana logs
podman logs kibana

# Check if Kibana can reach Elasticsearch
podman exec -it kibana curl http://elasticsearch:9200
```

### High CPU/Memory Usage

```bash
# Check which queries are slow
curl http://192.168.20.10:9200/_nodes/hot_threads

# Reduce heap size
# Edit docker-compose.yml and restart

# Adjust refresh interval (in Kibana)
# Stack Management → Index Patterns → Refresh every: 30s
```

### Disk Full

```bash
# Delete old indices
curl -X DELETE http://192.168.20.10:9200/homesec-ips-2024.01.01

# Or configure ILM to auto-delete

# Force merge old indices to free space
curl -X POST "http://192.168.20.10:9200/homesec-*/_forcemerge?max_num_segments=1"
```

## Performance Tuning

### Elasticsearch Heap Size

**Rule of thumb**: 50% of available RAM, max 32GB

With 64GB server RAM:
- Elasticsearch: 16-24GB
- Kibana: 2-4GB
- Logstash: 2-4GB (if used)
- Remaining: OS, other services

Edit `docker-compose.yml`:
```yaml
environment:
  - "ES_JAVA_OPTS=-Xms16g -Xmx16g"
```

### Index Shards

For single-node setup, use 1 shard per index:

```bash
# Set default shards
curl -X PUT "http://192.168.20.10:9200/_template/homesec_defaults" -H 'Content-Type: application/json' -d'
{
  "index_patterns": ["homesec-*"],
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  }
}'
```

### Query Performance

- Use index patterns with wildcards sparingly
- Set appropriate time ranges in Kibana
- Use filters instead of queries when possible
- Refresh less frequently (30s instead of 5s)

## Security

### Enable Authentication (Production)

If exposing to less trusted networks:

1. Edit `docker-compose.yml`:
```yaml
environment:
  - xpack.security.enabled=true
```

2. Generate passwords:
```bash
podman exec -it elasticsearch bin/elasticsearch-setup-passwords auto
```

3. Update Kibana config with username/password

4. Update Filebeat/Metricbeat configs with credentials

### HTTPS/TLS

For production, enable TLS on Elasticsearch and Kibana:
- Generate certificates
- Configure TLS in docker-compose.yml
- Update all clients to use HTTPS

## Maintenance

### Daily
- Check cluster health
- Monitor disk usage
- Review critical alerts in Kibana

### Weekly
- Review index sizes
- Check for slow queries
- Update dashboards as needed

### Monthly
- Review and adjust ILM policies
- Clean up old indices manually if needed
- Update ELK Stack to latest version
- Test backup restore

## Container Management

```bash
# Start services
podman-compose up -d

# Stop services
podman-compose down

# Restart specific service
podman-compose restart elasticsearch

# View logs
podman-compose logs -f elasticsearch

# Execute command in container
podman exec -it elasticsearch bash

# Update containers
podman-compose pull
podman-compose up -d

# Remove everything (DANGEROUS - deletes data)
podman-compose down -v
```

## Useful Elasticsearch Queries

```bash
# Count documents
curl http://192.168.20.10:9200/_count?pretty

# Search for alerts
curl -X GET "http://192.168.20.10:9200/homesec-ips-*/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "query": {
    "match": {
      "event_type": "alert"
    }
  }
}'

# Get top source IPs
curl -X GET "http://192.168.20.10:9200/homesec-*/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "aggs": {
    "top_ips": {
      "terms": {
        "field": "src_ip.keyword",
        "size": 10
      }
    }
  }
}'
```

## Related Documentation

- [Architecture](../../docs/architecture.md)
- [Installation Guide](../../docs/installation-guide.md)
- [Filebeat Configuration](../monitoring/README.md)
- [Kibana Dashboards](../../dashboards/kibana/README.md)
- Official Elastic docs: https://www.elastic.co/guide/
