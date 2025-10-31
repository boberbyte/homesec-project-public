# Suricata IPS on Rock Pi E

## Overview

Rock Pi E runs Suricata in **IPS (Intrusion Prevention System) mode** as a transparent bridge between the OpenWrt router and HP switch.

**Mode**: Inline bridge (eth0 ↔ eth1)
**Action**: Actively blocks malicious traffic
**RAM**: 1GB (limited, tuned for performance)
**CPU**: Quad-core ARM

## Network Position

```
OpenWrt Router (192.168.x.1)
        ↓ eth0
   [Rock Pi E]  ← Suricata IPS inline
        ↓ eth1
HP 2530 Switch (VLAN trunk)
```

## Features

- **Inline blocking**: Drops malicious packets in real-time
- **Transparent bridge**: No IP address, invisible to network
- **Low latency**: < 5ms added latency at 120 Mbit/s
- **Rule-based detection**: Emerging Threats, custom rules
- **JSON logging**: EVE format to ELK Stack
- **Protocol analysis**: HTTP, TLS, DNS, SSH, SMB, etc.

## Installation

### 1. Base OS Setup

Install Debian/Ubuntu on Rock Pi E:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    suricata \
    bridge-utils \
    tcpdump \
    net-tools \
    iperf3 \
    htop \
    vim
```

### 2. Configure Network Bridge

Create bridge between eth0 and eth1:

```bash
# Edit network interfaces
sudo nano /etc/network/interfaces

# Add bridge configuration:
auto lo
iface lo inet loopback

# Bridge (no IP address - transparent)
auto br0
iface br0 inet manual
    bridge_ports eth0 eth1
    bridge_stp off
    bridge_fd 0
    bridge_maxwait 0

# Bring up bridge
sudo systemctl restart networking

# Or manually:
sudo ip link set eth0 up
sudo ip link set eth1 up
sudo brctl addbr br0
sudo brctl addif br0 eth0
sudo brctl addif br0 eth1
sudo ip link set br0 up
```

### 3. Disable Hardware Offloading

For proper IPS operation:

```bash
# Disable offloading on eth0 and eth1
sudo ethtool -K eth0 gro off lro off tso off gso off
sudo ethtool -K eth1 gro off lro off tso off gso off

# Make permanent
sudo nano /etc/rc.local

# Add before "exit 0":
ethtool -K eth0 gro off lro off tso off gso off
ethtool -K eth1 gro off lro off tso off gso off
```

### 4. Install Suricata

```bash
# Add Suricata repository (if not in default repos)
sudo add-apt-repository ppa:oisf/suricata-stable
sudo apt update

# Install Suricata
sudo apt install suricata -y

# Check version
suricata --version
```

### 5. Configure Suricata

```bash
# Backup default config
sudo cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.bak

# Copy HomeSec config
sudo cp suricata.yaml /etc/suricata/suricata.yaml

# Create log directory
sudo mkdir -p /var/log/suricata
sudo chown suricata:suricata /var/log/suricata
```

### 6. Update Suricata Rules

```bash
# Update rules using suricata-update
sudo suricata-update

# Or manually specify sources
sudo suricata-update update-sources
sudo suricata-update enable-source et/open
sudo suricata-update enable-source oisf/trafficid

# Update rules
sudo suricata-update

# Verify rules
sudo suricata -T -c /etc/suricata/suricata.yaml
```

### 7. Configure IPS Mode

```bash
# Edit Suricata systemd service for IPS mode
sudo nano /etc/systemd/system/suricata.service

[Unit]
Description=Suricata Intrusion Prevention System
After=network.target

[Service]
Type=simple
Environment="SURICATA_OPTIONS=-c /etc/suricata/suricata.yaml --af-packet"
EnvironmentFile=-/etc/default/suricata
ExecStart=/usr/bin/suricata $SURICATA_OPTIONS
KillMode=mixed
Restart=on-failure

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
```

### 9. Verify IPS Operation

```bash
# Test 1: Check if Suricata is running
ps aux | grep suricata

# Test 2: Check if packets are being processed
sudo tail -f /var/log/suricata/stats.log

# Test 3: Check bridge is working
ping -c 4 192.168.20.10  # From a client

# Test 4: Test IPS blocking with EICAR test
# From a client:
curl http://www.eicar.org/download/eicar.com.txt

# Should be blocked, check alert:
sudo tail /var/log/suricata/fast.log
```

## Configuration Tuning

### For Low RAM (1GB)

Already configured in suricata.yaml:
- Flow memcap: 256MB
- Stream memcap: 256MB
- Defrag memcap: 128MB
- Minimal threading (2 worker threads)

### Adjusting IPS Actions

Edit `/etc/suricata/suricata.yaml`:

```yaml
# To change from DROP to ALERT only (testing)
action-order:
  - pass
  - alert  # Changed from drop
  - reject
  - drop
```

### Custom Rules

Create custom rules in `/etc/suricata/rules/local.rules`:

```
# Block specific IPs
drop ip 1.2.3.4 any -> $HOME_NET any (msg:"Blocked malicious IP"; sid:1000001; rev:1;)

# Alert on large uploads to Honeypot (potential data exfiltration)
alert tcp $HONEYPOT_NET any -> $EXTERNAL_NET any (msg:"Large upload from Honeypot"; flow:established,to_server; dsize:>1000000; sid:1000002; rev:1;)

# Drop known C2 traffic
drop http any any -> $EXTERNAL_NET any (msg:"Possible C2 beacon"; content:"X-Custom-Header"; http_header; sid:1000003; rev:1;)
```

Update rules:
```bash
sudo suricata-update
sudo systemctl restart suricata
```

## Monitoring

### Real-time Stats

```bash
# Watch stats
watch -n 5 'sudo suricatasc -c "dump-counters"'

# Watch alerts
sudo tail -f /var/log/suricata/fast.log

# Watch EVE JSON log
sudo tail -f /var/log/suricata/eve.json | jq .
```

### Performance Metrics

```bash
# CPU usage
htop

# Network throughput
sudo iftop -i eth0

# Dropped packets (should be near 0)
cat /sys/class/net/eth0/statistics/rx_dropped
cat /sys/class/net/eth1/statistics/tx_dropped
```

### Key Metrics

- **Capture.Kernel_packets**: Total packets seen
- **Capture.Kernel_drops**: Packets dropped by kernel (bad!)
- **Decoder.pkts**: Packets decoded by Suricata
- **Flow.memuse**: Memory used by flows
- **Tcp.sessions**: Active TCP sessions

## Troubleshooting

### High CPU Usage

```bash
# Check Suricata threads
ps -eLf | grep suricata

# Reduce worker threads in suricata.yaml:
threading:
  detect-thread-ratio: 0.5  # Reduce from 1.0

# Disable unused protocols in app-layer section
```

### Packets Being Dropped

```bash
# Check kernel drops
sudo ethtool -S eth0 | grep drop

# Increase ring buffer (in suricata.yaml):
af-packet:
  - interface: eth0
    ring-size: 4096  # Increase from 2048

# Check if RAM is full
free -h
```

### Suricata Not Starting

```bash
# Check config syntax
sudo suricata -T -c /etc/suricata/suricata.yaml

# Check logs
sudo journalctl -u suricata -n 100

# Run in foreground for debugging
sudo suricata -c /etc/suricata/suricata.yaml --af-packet -vvv
```

### Bridge Not Working

```bash
# Check bridge status
brctl show

# Check if interfaces are up
ip link show

# Manually test bridge
sudo brctl addbr br0
sudo brctl addif br0 eth0
sudo brctl addif br0 eth1
sudo ip link set br0 up
```

## Log Shipping to ELK

Filebeat on Rock Pi 4 SE collects logs via syslog or by reading eve.json.

### Option 1: Syslog (already configured)

Suricata sends logs to syslog, which forwards to Rock Pi 4 SE (192.168.20.20).

### Option 2: Direct File Reading (better)

Install Filebeat on Rock Pi E:

```bash
# Install Filebeat
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
sudo apt-get install apt-transport-https
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-8.x.list
sudo apt-get update && sudo apt-get install filebeat

# Configure Filebeat
sudo nano /etc/filebeat/filebeat.yml

filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/suricata/eve.json
  json.keys_under_root: true
  json.overwrite_keys: true
  fields:
    source: rockpi-e-ips
    sensor: HomeSec-IPS

output.elasticsearch:
  hosts: ["192.168.20.10:9200"]
  index: "homesec-ips-%{+yyyy.MM.dd}"

# Start Filebeat
sudo systemctl enable filebeat
sudo systemctl start filebeat
```

## Maintenance

### Daily

```bash
# Check for high alerts
sudo grep -c "Priority: 1" /var/log/suricata/fast.log

# Check resource usage
htop
free -h
```

### Weekly

```bash
# Update rules
sudo suricata-update
sudo systemctl reload suricata

# Rotate logs (if not using logrotate)
sudo systemctl restart suricata
```

### Monthly

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Update Suricata
sudo apt install --only-upgrade suricata

# Review tuning
sudo suricatasc -c "dump-counters" > /tmp/suricata-stats.txt
# Analyze drops, memory usage, etc.
```

## Performance Baseline

**Expected performance with 120 Mbit/s internet**:
- CPU usage: 20-40%
- RAM usage: 300-600MB
- Added latency: < 5ms
- Packet drops: < 0.1%

If performance degrades, tune suricata.yaml or disable unused features.

## Security Notes

- Rock Pi E has **no IP address** - it's a transparent bridge
- Cannot be accessed directly from network
- Must connect via console cable or enable SSH on local interface
- For management, use Rock Pi 4 SE as jump host

## Backup

```bash
# Backup configuration
sudo tar -czf /tmp/rockpi-e-ips-backup.tar.gz \
    /etc/suricata/ \
    /etc/network/interfaces \
    /var/lib/suricata/rules/

# Copy to server
scp /tmp/rockpi-e-ips-backup.tar.gz user@192.168.20.10:/mnt/raid/backups/
```

## Related Documentation

- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- [Rock Pi 4 SE IDS](../rockpi4-ids/README.md)
- Official Suricata docs: https://suricata.readthedocs.io/
