# BIND DNS Server

## Overview

BIND (Berkeley Internet Name Domain) DNS server provides internal name resolution for all VLANs in the HomeSec infrastructure.

**IP Address**: 192.168.20.53
**Domain**: homesec.local
**Purpose**: Internal DNS resolution, DNS logging for security analysis

## Features

- **Internal zone management**: homesec.local domain for internal services
- **Split-horizon DNS**: Different responses for internal vs external queries
- **Reverse DNS**: PTR records for all VLANs
- **Query logging**: All DNS queries logged for security analysis
- **Recursion**: Controlled recursion for internal networks only
- **DNSSEC**: Optional DNSSEC validation
- **Integration**: Logs forwarded to ELK Stack via Filebeat

## Network Configuration

### DNS Server Access by VLAN

| VLAN | Network | DNS Access | Notes |
|------|---------|------------|-------|
| VLAN 10 | 192.168.10.0/24 | ✓ Allow | Trusted devices |
| VLAN 20 | 192.168.20.0/24 | ✓ Allow | Infrastructure (DNS server here) |
| VLAN 30 | 192.168.30.0/24 | ✓ Allow | IoT/Guest |
| VLAN 40 | 192.168.40.0/24 | ✓ Allow | Lab VMs |
| VLAN 99 | 192.168.99.0/24 | ✓ Allow | Honeypot (monitored) |

All VLANs use 192.168.20.53 as primary DNS server.

## Installation

### 1. Install BIND

```bash
# On CentOS Server
sudo yum install -y bind bind-utils

# Verify installation
named -v
```

### 2. Configure BIND

```bash
# Backup default configuration
sudo cp /etc/named.conf /etc/named.conf.backup

# Copy HomeSec configuration
sudo cp named.conf /etc/named.conf
sudo cp named.conf.options /etc/named/named.conf.options

# Create zone directory
sudo mkdir -p /var/named/zones
sudo chown named:named /var/named/zones

# Copy zone files
sudo cp db.homesec.local /var/named/zones/
sudo cp db.192.168.* /var/named/zones/

# Set permissions
sudo chown named:named /var/named/zones/*
sudo chmod 644 /var/named/zones/*
```

### 3. Create Log Directory

```bash
# Create log directory
sudo mkdir -p /var/log/named
sudo chown named:named /var/log/named
sudo chmod 755 /var/log/named

# Configure logrotate
sudo nano /etc/logrotate.d/named

/var/log/named/*.log {
    daily
    rotate 30
    missingok
    compress
    delaycompress
    notifempty
    create 0644 named named
    postrotate
        systemctl reload named > /dev/null 2>&1 || true
    endscript
}
```

### 4. Configure Firewall

```bash
# Allow DNS traffic
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-services
```

### 5. Start BIND

```bash
# Test configuration
sudo named-checkconf /etc/named.conf

# Test zone files
sudo named-checkzone homesec.local /var/named/zones/db.homesec.local
sudo named-checkzone 20.168.192.in-addr.arpa /var/named/zones/db.192.168.20

# Enable and start service
sudo systemctl enable named
sudo systemctl start named

# Check status
sudo systemctl status named

# Check logs
sudo tail -f /var/log/named/queries.log
```

### 6. Test DNS Resolution

```bash
# From server
dig @localhost homesec.local
dig @localhost server.homesec.local

# From client (via VPN or internal network)
dig @192.168.20.53 server.homesec.local
nslookup server.homesec.local 192.168.20.53

# Test reverse DNS
dig -x 192.168.20.10 @192.168.20.53

# Test external resolution
dig @192.168.20.53 google.com
```

## Zone Configuration

### homesec.local (Internal Zone)

Key records in `db.homesec.local`:

```
server.homesec.local     A    192.168.20.10
dns.homesec.local        A    192.168.20.53
switch.homesec.local     A    192.168.20.11
ids.homesec.local        A    192.168.20.20
router.homesec.local     A    192.168.20.1

kibana.homesec.local     CNAME server.homesec.local
elk.homesec.local        CNAME server.homesec.local
```

### Reverse Zones

Reverse DNS for all VLANs:
- `db.192.168.10` - VLAN 10 (Trusted)
- `db.192.168.20` - VLAN 20 (Infrastructure)
- `db.192.168.30` - VLAN 30 (IoT/Guest)
- `db.192.168.40` - VLAN 40 (Lab VMs)
- `db.192.168.99` - VLAN 99 (Honeypot)

## DNS Logging

### Query Logging

All DNS queries are logged to `/var/log/named/queries.log` for security analysis.

```bash
# Watch queries in real-time
sudo tail -f /var/log/named/queries.log

# Search for specific domain
sudo grep "example.com" /var/log/named/queries.log

# Count queries by domain
sudo awk '{print $NF}' /var/log/named/queries.log | sort | uniq -c | sort -rn | head -20
```

### Security Monitoring

DNS logs are forwarded to Elasticsearch for analysis:

```bash
# Configure Filebeat to collect DNS logs
sudo nano /etc/filebeat/filebeat.yml

filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/named/queries.log
  fields:
    log_type: dns
    source: bind-server
  fields_under_root: false

# Restart Filebeat
sudo systemctl restart filebeat
```

### Interesting Queries to Monitor

- **DNS tunneling**: Unusually long domain names
- **DGA (Domain Generation Algorithm)**: Random-looking domains
- **Known malicious domains**: Queries to known bad domains
- **Honeypot queries**: DNS queries from VLAN 99

Example Kibana queries:
```
# Long domain names (potential tunneling)
log_type:dns AND query_length:>50

# Queries from honeypot
log_type:dns AND client_ip:192.168.99.*

# Queries to suspicious TLDs
log_type:dns AND (query:*.tk OR query:*.xyz OR query:*.top)
```

## Troubleshooting

### BIND Won't Start

```bash
# Check configuration syntax
sudo named-checkconf /etc/named.conf

# Check zone files
sudo named-checkzone homesec.local /var/named/zones/db.homesec.local

# Check logs
sudo journalctl -u named -n 50

# Check permissions
ls -la /var/named/zones/

# Run in foreground for debugging
sudo named -g -c /etc/named.conf
```

### DNS Not Resolving

```bash
# Test locally
dig @localhost homesec.local

# Check if BIND is listening
sudo netstat -tulpn | grep :53
sudo ss -tulpn | grep :53

# Check firewall
sudo firewall-cmd --list-services

# Test from client
dig @192.168.20.53 server.homesec.local

# Check query log
sudo tail -f /var/log/named/queries.log
```

### High Query Rate

```bash
# Check query rate
sudo tail -f /var/log/named/queries.log | pv -l > /dev/null

# Identify top queriers
sudo awk '{print $1}' /var/log/named/queries.log | sort | uniq -c | sort -rn | head -20

# Rate limit if necessary (in named.conf)
# Add to options:
# rate-limit {
#     responses-per-second 10;
# };
```

## Adding New DNS Records

### Add A Record

```bash
# Edit zone file
sudo nano /var/named/zones/db.homesec.local

# Add record
newhost    IN    A    192.168.20.50

# Increment serial number (YYYYMMDDNN format)
# Before: 2024011501
# After:  2024011502

# Check zone
sudo named-checkzone homesec.local /var/named/zones/db.homesec.local

# Reload zone
sudo rndc reload homesec.local

# Verify
dig @localhost newhost.homesec.local
```

### Add Reverse Record

```bash
# Edit reverse zone
sudo nano /var/named/zones/db.192.168.20

# Add PTR record
50    IN    PTR    newhost.homesec.local.

# Increment serial

# Check zone
sudo named-checkzone 20.168.192.in-addr.arpa /var/named/zones/db.192.168.20

# Reload
sudo rndc reload 20.168.192.in-addr.arpa

# Verify
dig -x 192.168.20.50 @localhost
```

## Security Features

### Access Control

Only internal networks can perform recursive queries:

```bash
# In named.conf
acl "trusted" {
    192.168.10.0/24;  # VLAN 10
    192.168.20.0/24;  # VLAN 20
    192.168.30.0/24;  # VLAN 30
    192.168.40.0/24;  # VLAN 40
    192.168.99.0/24;  # VLAN 99
    127.0.0.1;        # localhost
};

options {
    allow-query { trusted; };
    recursion yes;
    allow-recursion { trusted; };
};
```

### Query Rate Limiting

Prevent DNS amplification attacks:

```bash
# In named.conf options
rate-limit {
    responses-per-second 10;
    window 5;
};
```

### DNSSEC Validation (Optional)

```bash
# Enable DNSSEC validation
# In named.conf options
dnssec-enable yes;
dnssec-validation auto;
```

## Performance Tuning

### Cache Size

```bash
# In named.conf options
max-cache-size 256M;
max-cache-ttl 86400;    # 1 day
max-ncache-ttl 3600;    # 1 hour
```

### Concurrent Queries

```bash
# In named.conf options
recursive-clients 1000;
tcp-clients 100;
```

## Monitoring

### Check Stats

```bash
# Enable statistics
sudo rndc stats

# View stats
cat /var/named/data/named_stats.txt

# Query count
sudo rndc status
```

### Monitor with Metricbeat

Configure Metricbeat to collect BIND metrics (if using BIND 9.10+):

```yaml
# In metricbeat.yml
- module: bind
  period: 10s
  hosts: ["http://localhost:8053"]
  metricsets:
    - stats
```

## Backup

```bash
# Backup DNS configuration and zones
sudo tar -czf /tmp/dns-backup-$(date +%Y%m%d).tar.gz \
    /etc/named.conf \
    /etc/named/ \
    /var/named/zones/

# Copy to server backup location
sudo cp /tmp/dns-backup-*.tar.gz /mnt/raid/backups/
```

## Maintenance

### Daily

```bash
# Check logs for errors
sudo journalctl -u named --since today | grep -i error

# Monitor query volume
sudo wc -l /var/log/named/queries.log
```

### Weekly

```bash
# Update root hints (if using recursion)
sudo wget -O /var/named/named.ca https://www.internic.net/domain/named.root
sudo chown named:named /var/named/named.ca

# Reload configuration
sudo systemctl reload named
```

### Monthly

```bash
# Update BIND
sudo yum update bind -y

# Review logs for unusual patterns
sudo journalctl -u named --since "1 month ago" | less

# Backup configuration
sudo tar -czf /mnt/raid/backups/dns-monthly-$(date +%Y%m%d).tar.gz \
    /etc/named.conf /etc/named/ /var/named/zones/
```

## Integration with Other Components

### DHCP Integration

OpenWrt DHCP server points clients to this DNS server:
- Primary DNS: 192.168.20.53
- Secondary DNS: 1.1.1.1 (Cloudflare)

### ELK Integration

DNS query logs forwarded to Elasticsearch:
- Index: `homesec-dns-*`
- Contains: client IP, query domain, query type, response

### Suricata Integration

Suricata also logs DNS queries from packet captures:
- Cross-reference BIND logs with Suricata DNS logs
- Detect DNS tunneling, DGA, exfiltration

## Related Documentation

- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- [OpenWrt DHCP Configuration](../../network/openwrt/README.md)
- BIND Documentation: https://bind9.readthedocs.io/
