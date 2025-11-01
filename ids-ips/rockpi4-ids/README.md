# Suricata IDS on Rock Pi 4 SE

## Overview

Rock Pi 4 SE runs Suricata in **IDS (Intrusion Detection System) mode** for passive network monitoring. It receives all network traffic via a SPAN (mirror) port on the HP switch.

**Mode**: Passive monitoring (read-only)
**Action**: Alerts only, no blocking
**RAM**: 4GB (allows aggressive detection)
**CPU**: Hexa-core ARM (RK3399)

## Network Position

```
HP Switch Port 22 (SPAN/Mirror) → eth0 → [Rock Pi 4 SE]
                                            ├─ Suricata IDS
                                            ├─ Filebeat
                                            └─ Metricbeat

All logs → Elasticsearch (192.168.20.10:9200)
```

## Features

- **Passive monitoring**: No impact on network traffic
- **Full visibility**: Sees all network traffic via SPAN port
- **Advanced detection**: More aggressive rules (4GB RAM)
- **Protocol analysis**: Deep inspection of HTTP, TLS, DNS, SSH, SMB, FTP, etc.
- **File extraction**: Extract suspicious files from traffic
- **TLS fingerprinting**: Identify encrypted traffic patterns
- **DNS logging**: All DNS queries logged
- **Data collectors**: Filebeat + Metricbeat send data to ELK

## Installation

### 1. Base OS Setup

Install Debian/Ubuntu on Rock Pi 4 SE:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    suricata \
    tcpdump \
    net-tools \
    iperf3 \
    htop \
    vim \
    jq \
    curl
```

### 2. Configure Network Interface

Rock Pi 4 SE has a static IP on VLAN 20:

```bash
# Edit network interfaces
sudo nano /etc/network/interfaces

# Configure eth0 with static IP
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.20.20
    netmask 255.255.255.0
    gateway 192.168.20.1
    dns-nameservers 192.168.20.53 1.1.1.1

# Apply changes
sudo systemctl restart networking

# Verify
ip addr show eth0
ping -c 4 192.168.20.10
```

### 3. Verify SPAN Port Traffic

The Rock Pi 4 SE should see ALL network traffic:

```bash
# Check if receiving mirrored traffic
sudo tcpdump -i eth0 -c 100

# You should see traffic from multiple sources (not just this device)
# Check for variety of IPs and protocols

# Monitor traffic volume
sudo iftop -i eth0
```

If you don't see mirrored traffic, verify HP switch SPAN configuration (see `network/hp-switch/README.md`).

### 4. Install Suricata

```bash
# Add Suricata repository
sudo add-apt-repository ppa:oisf/suricata-stable
sudo apt update

# Install Suricata
sudo apt install suricata -y

# Check version (should be 7.0+)
suricata --version
```

### 5. Configure Suricata

```bash
# Backup default config
sudo cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.bak

# Copy HomeSec IDS config
sudo cp suricata.yaml /etc/suricata/suricata.yaml

# Create log directory
sudo mkdir -p /var/log/suricata
sudo chown suricata:suricata /var/log/suricata
```

### 6. Update Suricata Rules

```bash
# Update rules using suricata-update
sudo suricata-update

# Enable additional sources
sudo suricata-update update-sources
sudo suricata-update enable-source et/open
sudo suricata-update enable-source oisf/trafficid
sudo suricata-update enable-source tgreen/hunting
sudo suricata-update enable-source sslbl/ssl-fp-blacklist

# Update all rules
sudo suricata-update

# Verify configuration
sudo suricata -T -c /etc/suricata/suricata.yaml
```

### 7. Configure Suricata Service

```bash
# Edit Suricata systemd service
sudo nano /etc/systemd/system/suricata.service

[Unit]
Description=Suricata Intrusion Detection System
After=network.target

[Service]
Type=simple
Environment="SURICATA_OPTIONS=-c /etc/suricata/suricata.yaml -i eth0"
EnvironmentFile=-/etc/default/suricata
ExecStart=/usr/bin/suricata $SURICATA_OPTIONS
KillMode=mixed
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target

# Reload systemd
sudo systemctl daemon-reload
```

### 8. Start Suricata

```bash
# Enable on boot
sudo systemctl enable suricata

# Start service
sudo systemctl start suricata

# Check status
sudo systemctl status suricata

# Check logs
sudo tail -f /var/log/suricata/suricata.log
sudo tail -f /var/log/suricata/fast.log

# Watch EVE JSON output
sudo tail -f /var/log/suricata/eve.json | jq .
```

### 9. Install Filebeat

Filebeat ships Suricata logs to Elasticsearch:

```bash
# Add Elastic repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
sudo apt-get install apt-transport-https
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt-get update

# Install Filebeat
sudo apt-get install filebeat

# Enable Suricata module
sudo filebeat modules enable suricata

# Configure Suricata module
sudo nano /etc/filebeat/modules.d/suricata.yml

- module: suricata
  eve:
    enabled: true
    var.paths: ["/var/log/suricata/eve.json"]

# Configure output to Elasticsearch
sudo nano /etc/filebeat/filebeat.yml

# Disable default output
#output.elasticsearch:

# Add Elasticsearch output
output.elasticsearch:
  hosts: ["192.168.20.10:9200"]
  index: "homesec-ids-%{+yyyy.MM.dd}"

setup.template.name: "homesec-ids"
setup.template.pattern: "homesec-ids-*"

# Add fields for identification
fields:
  source: rockpi4-ids
  sensor: HomeSec-IDS
  location: VLAN20

# Test configuration
sudo filebeat test config
sudo filebeat test output

# Enable and start Filebeat
sudo systemctl enable filebeat
sudo systemctl start filebeat

# Check status
sudo systemctl status filebeat
```

### 10. Install Metricbeat

Metricbeat monitors system and Suricata metrics:

```bash
# Install Metricbeat
sudo apt-get install metricbeat

# Enable system module (already enabled by default)
sudo metricbeat modules enable system

# Configure output
sudo nano /etc/metricbeat/metricbeat.yml

# Disable default output
#output.elasticsearch:

# Add Elasticsearch output
output.elasticsearch:
  hosts: ["192.168.20.10:9200"]
  index: "homesec-metrics-%{+yyyy.MM.dd}"

setup.template.name: "homesec-metrics"
setup.template.pattern: "homesec-metrics-*"

# Add fields
fields:
  source: rockpi4-ids
  host: rockpi4-se

# Configure system module
sudo nano /etc/metricbeat/modules.d/system.yml

- module: system
  period: 10s
  metricsets:
    - cpu
    - load
    - memory
    - network
    - process
    - process_summary
    - filesystem
    - diskio
  processes: ['suricata', 'filebeat']

# Test and start
sudo metricbeat test config
sudo metricbeat test output

sudo systemctl enable metricbeat
sudo systemctl start metricbeat

# Check status
sudo systemctl status metricbeat
```

### 11. Verify Data Flow to ELK

```bash
# Check Filebeat is sending data
curl -X GET "http://192.168.20.10:9200/_cat/indices/homesec-ids-*?v"

# Check Metricbeat is sending data
curl -X GET "http://192.168.20.10:9200/_cat/indices/homesec-metrics-*?v"

# Query recent alerts
curl -X GET "http://192.168.20.10:9200/homesec-ids-*/_search?size=10&sort=@timestamp:desc&pretty"
```

## Configuration Tuning

### For 4GB RAM (Aggressive Detection)

Already configured in suricata.yaml:
- Flow memcap: 512MB
- Stream memcap: 1GB
- Defrag memcap: 256MB
- More worker threads (4)
- All protocols enabled
- File extraction enabled
- TLS fingerprinting enabled

### Custom Detection Rules

Create custom rules in `/etc/suricata/rules/local.rules`:

```
# Alert on connections to Honeypot (VLAN 99)
alert tcp any any -> 192.168.99.0/24 any (msg:"Connection to Honeypot network"; sid:2000001; rev:1;)

# Alert on large data transfers
alert tcp any any -> any any (msg:"Large data transfer detected"; dsize:>10000000; sid:2000002; rev:1;)

# Detect SSH brute force
alert ssh any any -> $HOME_NET 22 (msg:"Potential SSH brute force"; detection_filter:track by_src, count 5, seconds 60; sid:2000003; rev:1;)

# Detect DNS tunneling (unusually long DNS queries)
alert dns any any -> any 53 (msg:"Possible DNS tunneling"; dns_query; content:"."; isdataat:50,relative; sid:2000004; rev:1;)

# Detect beaconing (regular intervals)
alert tcp $HOME_NET any -> $EXTERNAL_NET any (msg:"Possible C2 beaconing"; flow:established; detection_filter:track by_src, count 10, seconds 300; sid:2000005; rev:1;)
```

Update rules:
```bash
sudo suricata-update
sudo systemctl reload suricata
```

### Enable File Extraction

Edit `/etc/suricata/suricata.yaml`:

```yaml
file-store:
  version: 2
  enabled: yes
  dir: /var/log/suricata/files
  force-magic: yes
  force-hash: [md5, sha256]
```

Create directory:
```bash
sudo mkdir -p /var/log/suricata/files
sudo chown suricata:suricata /var/log/suricata/files
```

## Monitoring

### Real-time Stats

```bash
# Watch Suricata stats
watch -n 5 'sudo suricatasc -c "dump-counters" | grep -E "capture\.|decoder\.|flow\."'

# Watch alerts in real-time
sudo tail -f /var/log/suricata/fast.log

# Watch EVE JSON with formatting
sudo tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="alert")'

# Monitor specific event types
sudo tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="dns")' | jq -c '{timestamp:.timestamp,query:.dns.rrname,answer:.dns.answers}'
```

### Performance Metrics

```bash
# CPU usage
htop

# Network traffic
sudo iftop -i eth0

# Disk I/O
sudo iotop

# Suricata packet stats
sudo suricatasc -c "dump-counters" | grep -i packet

# Check for drops
cat /var/log/suricata/stats.log | grep drop
```

### Key Metrics to Monitor

- **Capture.Kernel_packets**: Total packets processed
- **Capture.Kernel_drops**: Packets dropped (should be 0)
- **Decoder.pkts**: Successfully decoded packets
- **Flow.memuse**: Flow memory usage
- **Tcp.sessions**: Active TCP connections
- **App_layer.\***: Protocol-specific statistics

## Troubleshooting

### No Traffic Being Captured

```bash
# Verify SPAN port configuration on switch
# See network/hp-switch/README.md

# Check if eth0 is receiving traffic
sudo tcpdump -i eth0 -c 100

# Check interface is up and in promiscuous mode
ip link show eth0
sudo ip link set eth0 promisc on

# Verify Suricata is listening
sudo netstat -tulpn | grep suricata
ps aux | grep suricata
```

### High CPU Usage

```bash
# Check which processes are using CPU
htop

# Reduce Suricata worker threads in suricata.yaml
threading:
  cpu-affinity:
    - worker-cpu-set:
        cpu: [ 0,1,2 ]  # Reduce from 0-3

# Disable unused protocols
app-layer:
  protocols:
    ftp:
      enabled: no  # Disable if not needed
```

### Disk Space Full

```bash
# Check disk usage
df -h

# Check Suricata log size
du -sh /var/log/suricata/

# Rotate logs
sudo systemctl restart suricata

# Configure log rotation
sudo nano /etc/logrotate.d/suricata

/var/log/suricata/*.log /var/log/suricata/*.json {
    daily
    rotate 7
    missingok
    compress
    delaycompress
    notifempty
    create 640 suricata suricata
    postrotate
        systemctl reload suricata > /dev/null 2>&1 || true
    endscript
}
```

### Filebeat Not Sending Data

```bash
# Check Filebeat status
sudo systemctl status filebeat

# Check Filebeat logs
sudo journalctl -u filebeat -n 100

# Test output to Elasticsearch
sudo filebeat test output

# Check connectivity to Elasticsearch
curl http://192.168.20.10:9200

# Manual send test
sudo filebeat test output -c /etc/filebeat/filebeat.yml
```

### Suricata Not Generating Alerts

```bash
# Verify rules are loaded
sudo suricatasc -c "ruleset-stats"

# Test with EICAR or malicious domain
curl http://testmyids.com

# Check fast.log for alerts
sudo tail -f /var/log/suricata/fast.log

# Verify rule files exist
ls -la /var/lib/suricata/rules/

# Reload rules
sudo suricatasc -c "reload-rules"
```

## Security Analysis Use Cases

### 1. Honeypot Traffic Analysis

Monitor all traffic to/from VLAN 99 (Honeypot):

```bash
# Real-time honeypot alerts
sudo tail -f /var/log/suricata/eve.json | jq 'select(.dest_ip | startswith("192.168.99."))'

# Create Kibana dashboard for honeypot activity
# Filter: dest_ip: 192.168.99.0/24 OR src_ip: 192.168.99.0/24
```

### 2. DNS Monitoring

Track all DNS queries:

```bash
# Watch DNS queries
sudo tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="dns") | {query:.dns.rrname, type:.dns.rrtype, answer:.dns.answers}'

# Detect DNS exfiltration attempts
# Look for unusually long domain names or high query frequency
```

### 3. TLS Certificate Monitoring

Track TLS connections and certificates:

```bash
# Extract TLS info
sudo tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="tls") | {server:.dest_ip, sni:.tls.sni, issuer:.tls.issuerdn}'

# Identify self-signed certificates (potential MITM)
```

### 4. File Transfer Detection

Monitor file downloads and uploads:

```bash
# Watch file transfers
sudo tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="fileinfo")'

# Check extracted files
ls -lah /var/log/suricata/files/

# Calculate file hashes and check against VirusTotal
```

## Integration with ELK Stack

### Kibana Dashboard Ideas

1. **Alert Overview Dashboard**
   - Alert severity distribution
   - Top alert signatures
   - Alert timeline (24h/7d)
   - Top source/destination IPs

2. **Network Traffic Dashboard**
   - Protocol distribution
   - Top talkers (source IPs)
   - Top destinations
   - Traffic volume over time

3. **Honeypot Activity Dashboard**
   - Attacks on honeypot
   - Attack source countries (GeoIP)
   - Attack types/signatures
   - Attacker behavior patterns

4. **DNS Analysis Dashboard**
   - Top queried domains
   - DNS query types
   - Potential DNS tunneling
   - Blocklist hits

5. **TLS/SSL Dashboard**
   - TLS versions in use
   - Certificate issuers
   - Self-signed certificates
   - JA3 fingerprints

### Example Kibana Queries

```
# High severity alerts
event_type:"alert" AND alert.severity:[1 TO 2]

# Honeypot traffic
(dest_ip:192.168.99.0/24 OR src_ip:192.168.99.0/24)

# DNS queries to suspicious TLDs
event_type:"dns" AND dns.rrname:(*xyz OR *.tk OR *.ml)

# Large file transfers
event_type:"fileinfo" AND fileinfo.size:>10000000

# TLS connections to non-standard ports
event_type:"tls" AND NOT dest_port:443
```

## Maintenance

### Daily

```bash
# Check for critical alerts
sudo grep "Priority: 1" /var/log/suricata/fast.log | tail -20

# Check system resources
htop
df -h

# Verify services are running
sudo systemctl status suricata filebeat metricbeat
```

### Weekly

```bash
# Update Suricata rules
sudo suricata-update
sudo systemctl reload suricata

# Check Elasticsearch indices
curl "http://192.168.20.10:9200/_cat/indices/homesec-*?v&s=index"

# Review top alerts in Kibana
```

### Monthly

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Suricata
sudo apt install --only-upgrade suricata

# Update Filebeat and Metricbeat
sudo apt install --only-upgrade filebeat metricbeat

# Backup configuration
sudo tar -czf /tmp/rockpi4-ids-backup-$(date +%Y%m%d).tar.gz \
    /etc/suricata/ \
    /etc/filebeat/ \
    /etc/metricbeat/ \
    /var/lib/suricata/rules/

# Copy to server
scp /tmp/rockpi4-ids-backup-*.tar.gz user@192.168.20.10:/mnt/raid/backups/
```

### Quarterly

```bash
# Review and tune detection rules
# Disable noisy rules that generate false positives
# Add custom rules based on observed traffic patterns

# Performance review
# Analyze Suricata stats over time
# Adjust resource allocation if needed
```

## Performance Baseline

**Expected performance with 120 Mbit/s traffic via SPAN**:
- CPU usage: 30-50%
- RAM usage: 1-2GB
- Packet drops: 0%
- Alert rate: Varies (depends on traffic/rules)

## Security Notes

- Rock Pi 4 SE is on management VLAN (VLAN 20)
- Only accessible via VPN (WireGuard)
- Passive monitoring - does not block traffic
- All logs sent to Elasticsearch for analysis
- Regular rule updates critical for detection accuracy

## Backup

```bash
# Full backup script
sudo bash -c 'cat > /usr/local/bin/backup-ids.sh << EOF
#!/bin/bash
BACKUP_DIR="/mnt/raid/backups"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="rockpi4-ids-\${DATE}.tar.gz"

tar -czf /tmp/\${BACKUP_FILE} \
    /etc/suricata/ \
    /etc/filebeat/ \
    /etc/metricbeat/ \
    /var/lib/suricata/rules/

scp /tmp/\${BACKUP_FILE} user@192.168.20.10:\${BACKUP_DIR}/
rm /tmp/\${BACKUP_FILE}

echo "Backup completed: \${BACKUP_FILE}"
EOF'

sudo chmod +x /usr/local/bin/backup-ids.sh

# Add to cron (weekly)
(crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/backup-ids.sh") | crontab -
```

## Related Documentation

- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- [Rock Pi E IPS](../rockpi-e-ips/README.md)
- [HP Switch SPAN Configuration](../../network/hp-switch/README.md)
- [ELK Stack Setup](../../server/elk-stack/README.md)
- Official Suricata docs: https://suricata.readthedocs.io/
- Filebeat docs: https://www.elastic.co/guide/en/beats/filebeat/current/index.html
