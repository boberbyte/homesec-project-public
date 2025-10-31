# HomeSec - Installation Guide

## Overview

This guide walks through the complete installation of HomeSec from scratch.

**Estimated time**: 8-12 hours (depending on experience)

**Prerequisites**:
- All hardware components ready
- Basic Linux/networking knowledge
- Console access to all devices
- Internet connection for package downloads

## Installation Order

The components must be installed in this specific order due to dependencies:

1. Network Infrastructure (Switch + Router)
2. WireGuard VPN
3. CentOS Server Base
4. ELK Stack (Elasticsearch + Kibana)
5. Rock Pi E (IPS)
6. Rock Pi 4 SE (IDS + Collectors)
7. BIND DNS
8. NAS (Samba/NFS)
9. Backup System
10. T-Pot Honeypot
11. Monitoring & Dashboards

## Phase 1: Network Infrastructure

### 1.1 HP Switch Configuration

**Time**: 1-2 hours

1. Connect to switch via console cable
2. Set management IP: 192.168.20.11
3. Configure VLANs (10, 20, 30, 40, 99)
4. Configure port mirroring (SPAN to port 22)
5. Enable PoE on ports 11-16 (WiFi APs)
6. Save configuration

**Documentation**: [HP Switch README](../network/hp-switch/README.md)

**Verification**:
```bash
show vlan
show mirror
show power-over-ethernet brief
```

### 1.2 OpenWrt Router Configuration

**Time**: 2-3 hours

1. Install OpenWrt on router
2. Configure VLAN interfaces
3. Configure DHCP per VLAN
4. Configure firewall zones and rules
5. Configure logging to Rock Pi 4 SE
6. Save configuration

**Documentation**: [OpenWrt README](../network/openwrt/README.md)

**Verification**:
```bash
ip addr show
iptables -L -v -n
cat /tmp/dhcp.leases
```

### 1.3 WireGuard VPN

**Time**: 1 hour

1. Generate server keys
2. Configure WireGuard on OpenWrt
3. Generate client keys
4. Create client configurations
5. Test VPN connection

**Documentation**: [WireGuard README](../vpn/wireguard/README.md)

**Verification**:
```bash
wg show
ping 192.168.20.1  # From VPN client
```

## Phase 2: CentOS Server

### 2.1 Base OS Installation

**Time**: 1 hour

1. Install CentOS Stream 9 (minimal)
2. Configure network (VLAN 20)
3. Set static IP: 192.168.20.10
4. Update system
5. Install essential packages

```bash
# Set hostname
hostnamectl set-hostname homesec-server

# Update system
dnf update -y

# Install essentials
dnf install -y vim git curl wget htop iotop iftop \
  net-tools bind-utils tcpdump rsync
```

### 2.2 RAID Configuration

**Time**: 30 minutes

```bash
# Check disks
lsblk

# Create RAID 1 (or RAID 10 if 4 disks)
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc

# Format
mkfs.ext4 /dev/md0

# Mount
mkdir -p /mnt/raid
mount /dev/md0 /mnt/raid

# Add to fstab
echo "/dev/md0 /mnt/raid ext4 defaults 0 2" >> /etc/fstab

# Verify
cat /proc/mdstat
```

### 2.3 Podman Installation

**Time**: 15 minutes

```bash
# Install Podman
dnf install -y podman podman-compose podman-docker

# Enable Podman socket
systemctl enable --now podman.socket

# Verify
podman --version
```

## Phase 3: ELK Stack

### 3.1 Elasticsearch

**Time**: 1 hour

**Documentation**: [ELK Stack README](../server/elk-stack/README.md)

```bash
# Create directories
mkdir -p /opt/elk/{elasticsearch,kibana,logstash}/data
mkdir -p /opt/elk/elasticsearch/config

# Create podman network
podman network create elk

# Run Elasticsearch
podman run -d \
  --name elasticsearch \
  --network elk \
  -p 9200:9200 \
  -p 9300:9300 \
  -e "discovery.type=single-node" \
  -e "ES_JAVA_OPTS=-Xms4g -Xmx4g" \
  -e "xpack.security.enabled=false" \
  -v /opt/elk/elasticsearch/data:/usr/share/elasticsearch/data:Z \
  docker.elastic.co/elasticsearch/elasticsearch:8.11.0

# Wait for startup
sleep 60

# Verify
curl http://192.168.20.10:9200
```

### 3.2 Kibana

**Time**: 30 minutes

```bash
# Run Kibana
podman run -d \
  --name kibana \
  --network elk \
  -p 443:5601 \
  -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
  -e "SERVER_HOST=0.0.0.0" \
  -v /opt/elk/kibana/data:/usr/share/kibana/data:Z \
  docker.elastic.co/kibana/kibana:8.11.0

# Wait for startup
sleep 60

# Verify
curl http://192.168.20.10:443
```

### 3.3 Logstash (Optional)

**Time**: 30 minutes

For advanced log processing and enrichment.

```bash
# Run Logstash
podman run -d \
  --name logstash \
  --network elk \
  -p 5044:5044 \
  -p 5000:5000 \
  -e "LS_JAVA_OPTS=-Xms1g -Xmx1g" \
  -v /opt/elk/logstash/pipeline:/usr/share/logstash/pipeline:Z \
  -v /opt/elk/logstash/data:/usr/share/logstash/data:Z \
  docker.elastic.co/logstash/logstash:8.11.0
```

## Phase 4: IDS/IPS

### 4.1 Rock Pi E - IPS (Inline Bridge)

**Time**: 2-3 hours

**Documentation**: [Rock Pi E IPS README](../ids-ips/rockpi-e-ips/README.md)

1. Install Debian/Ubuntu on Rock Pi E
2. Configure network bridge (eth0 ↔ eth1)
3. Disable hardware offloading
4. Install Suricata
5. Configure Suricata for IPS mode
6. Update rules
7. Test IPS blocking

**Verification**:
```bash
# Check bridge
brctl show

# Check Suricata
systemctl status suricata
tail -f /var/log/suricata/fast.log

# Test from client
curl http://www.eicar.org/download/eicar.com.txt  # Should be blocked
```

### 4.2 Rock Pi 4 SE - IDS (Passive)

**Time**: 2-3 hours

**Documentation**: [Rock Pi 4 SE IDS README](../ids-ips/rockpi4-ids/README.md)

1. Install Debian/Ubuntu on Rock Pi 4 SE
2. Configure static IP: 192.168.20.20
3. Install Suricata
4. Configure Suricata for passive IDS mode
5. Update rules
6. Verify SPAN port traffic

**Verification**:
```bash
# Check traffic from SPAN port
tcpdump -i eth0 -c 100

# Check Suricata
systemctl status suricata
tail -f /var/log/suricata/eve.json | jq .
```

## Phase 5: Data Collection

### 5.1 Filebeat on Rock Pi 4 SE

**Time**: 1 hour

**Documentation**: [Filebeat Config](../server/monitoring/filebeat-rockpi4.yml)

1. Install Filebeat
2. Configure inputs (Suricata, syslog, etc.)
3. Configure output to Elasticsearch
4. Start Filebeat

```bash
# Install
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
sudo apt-get install filebeat

# Configure
sudo cp filebeat-rockpi4.yml /etc/filebeat/filebeat.yml

# Start
sudo systemctl enable filebeat
sudo systemctl start filebeat

# Verify
filebeat test output
```

### 5.2 Metricbeat on All Hosts

**Time**: 1 hour

Install on: CentOS server, Rock Pi E, Rock Pi 4 SE, OpenWrt (optional)

```bash
# Install
sudo apt-get install metricbeat  # or dnf install metricbeat

# Configure
sudo nano /etc/metricbeat/metricbeat.yml

# Start
sudo systemctl enable metricbeat
sudo systemctl start metricbeat
```

## Phase 6: Additional Services

### 6.1 BIND DNS

**Time**: 1 hour

**Documentation**: [BIND Config](../server/dns/README.md)

1. Install BIND
2. Configure zones
3. Configure logging
4. Point all VLANs to DNS server

### 6.2 NAS (Samba/NFS)

**Time**: 1 hour

**Documentation**: [NAS Config](../server/nas/README.md)

1. Install Samba and NFS
2. Create shares
3. Configure access controls
4. Test from clients

### 6.3 T-Pot Honeypot

**Time**: 2 hours

1. Create Alma Linux VM
2. Install T-Pot
3. Configure VLAN 99 network
4. Configure firewall isolation
5. Configure logging to ELK

### 6.4 Backup System

**Time**: 1 hour

**Documentation**: [Backup Config](../server/backup/README.md)

1. Install Borg Backup
2. Configure backup scripts
3. Setup cron jobs
4. Test backup and restore

## Phase 7: Monitoring & Dashboards

### 7.1 Kibana Index Patterns

**Time**: 30 minutes

1. Access Kibana: https://192.168.20.10:443
2. Create index patterns:
   - `homesec-ips-*` (Rock Pi E IPS)
   - `homesec-ids-*` (Rock Pi 4 SE IDS)
   - `homesec-tpot-*` (T-Pot Honeypot)
   - `metricbeat-*` (System metrics)
   - `filebeat-*` (General logs)

### 7.2 Import Dashboards

**Time**: 1 hour

**Documentation**: [Dashboard Templates](../dashboards/kibana/README.md)

1. Import dashboard JSON files
2. Customize for your environment
3. Create alerts

## Phase 8: Verification & Testing

### 8.1 Network Connectivity Test

```bash
# From Trusted VLAN (192.168.10.x)
ping 192.168.20.10  # Server - should work
ping 192.168.30.10  # IoT VLAN - should fail
ping 192.168.99.10  # Honeypot - should fail

# From VPN
ping 192.168.20.10  # Server - should work
ping 192.168.10.100  # Trusted - should fail
```

### 8.2 IPS/IDS Test

```bash
# Test 1: EICAR malware test
curl http://www.eicar.org/download/eicar.com.txt

# Check alerts
tail /var/log/suricata/fast.log  # On both Rock Pis

# Test 2: SQL injection attempt
curl "http://192.168.20.10/test?id=1' OR '1'='1"

# Should see alerts in Kibana
```

### 8.3 Honeypot Test

```bash
# From internet (or simulate)
ssh root@<your-public-ip>:2222

# Check T-Pot logs in Kibana
# Should see SSH honeypot activity
```

### 8.4 Dashboard Verification

1. Open Kibana: https://192.168.20.10:443
2. Check data is flowing:
   - Security Events (IPS/IDS alerts)
   - System Health (CPU, RAM, disk)
   - Network Traffic (bandwidth, top talkers)
   - Honeypot Activity (attacks, malware)

## Phase 9: Optimization

### 9.1 Performance Tuning

- Adjust Suricata worker threads
- Tune Elasticsearch heap size
- Configure log retention
- Set up index lifecycle policies

### 9.2 Alert Tuning

- Reduce false positives
- Create custom rules
- Configure alerting thresholds
- Set up email/Slack notifications

## Troubleshooting

### Common Issues

**Issue**: No traffic in IDS
- Check SPAN port configuration on switch
- Verify tcpdump sees traffic on Rock Pi 4 SE eth0

**Issue**: High CPU on Rock Pi E
- Reduce Suricata worker threads
- Disable unused protocols
- Consider hardware upgrade if needed

**Issue**: Kibana not accessible
- Check Elasticsearch is running: `curl http://192.168.20.10:9200`
- Check Kibana container: `podman logs kibana`
- Check firewall rules

**Issue**: VPN not connecting
- Verify WireGuard is running: `wg show`
- Check firewall allows UDP 51820
- Verify client config has correct server public key

## Maintenance Schedule

### Daily
- Check Kibana for critical alerts
- Verify backup ran successfully

### Weekly
- Update Suricata rules
- Review dashboard for anomalies
- Test VPN connection

### Monthly
- Update all systems
- Review and tune alert rules
- Run RAID scrub
- Test backup restore

### Quarterly
- Rotate VPN keys
- Security audit
- Capacity planning review
- Update documentation

## Security Checklist

- [ ] All default passwords changed
- [ ] VPN only access to management interfaces
- [ ] T-Pot honeypot properly isolated
- [ ] Firewall rules tested and verified
- [ ] Backups tested and working
- [ ] Monitoring and alerting functional
- [ ] All systems updated to latest versions
- [ ] SSH key-based auth enabled (passwords disabled)
- [ ] Unnecessary services disabled
- [ ] Log retention configured

## Support & Resources

- [Architecture Documentation](architecture.md)
- [Network Design](network-design.md)
- Component-specific READMEs in each directory
- Suricata docs: https://suricata.readthedocs.io/
- Elastic docs: https://www.elastic.co/guide/
- OpenWrt docs: https://openwrt.org/docs/

## Next Steps

After installation:
1. Monitor system for 1 week to establish baselines
2. Tune alert thresholds to reduce false positives
3. Add custom Suricata rules for your environment
4. Expand Kibana dashboards as needed
5. Document any customizations made

## Estimated Total Time

- **Minimum**: 8 hours (experienced user, no issues)
- **Average**: 12 hours (typical installation)
- **Maximum**: 20+ hours (first time, troubleshooting)

**Recommendation**: Plan for 2-3 days, working a few hours each day.
