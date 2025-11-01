# OpenWrt Firewall Rules - Detailed Documentation

## Overview

This directory contains detailed documentation of all OpenWrt firewall rules, zones, and forwarding policies for the HomeSec network.

**Router**: OpenWrt (192.168.20.1)
**Firewall**: iptables/nftables managed by UCI

## Firewall Architecture

```
Internet (WAN)
    ↓
OpenWrt Router
    ├─ VLAN 10 (Trusted)      - Full internet access
    ├─ VLAN 20 (Infrastructure) - Full internet access + inter-VLAN mgmt
    ├─ VLAN 30 (IoT/Guest)    - Internet only, isolated
    ├─ VLAN 40 (Lab VMs)      - Internet + VLAN 20 access
    └─ VLAN 99 (Honeypot)     - Internet + limited VLAN 20 (DNS, ES)
```

## Firewall Zones

### Zone: WAN (Internet)
- **Input**: REJECT
- **Output**: ACCEPT
- **Forward**: REJECT
- **Masquerading**: Enabled
- **MSS Clamping**: Enabled

### Zone: VLAN 10 (Trusted Devices)
- **Input**: ACCEPT
- **Output**: ACCEPT
- **Forward**: ACCEPT
- **Network**: 192.168.10.0/24

### Zone: VLAN 20 (Infrastructure)
- **Input**: ACCEPT
- **Output**: ACCEPT
- **Forward**: ACCEPT
- **Network**: 192.168.20.0/24
- **Special**: Management network, VPN terminates here

### Zone: VLAN 30 (IoT/Guest)
- **Input**: REJECT
- **Output**: REJECT
- **Forward**: REJECT
- **Network**: 192.168.30.0/24
- **Isolation**: Complete isolation from other VLANs

### Zone: VLAN 40 (Lab VMs)
- **Input**: ACCEPT
- **Output**: ACCEPT
- **Forward**: ACCEPT
- **Network**: 192.168.40.0/24

### Zone: VLAN 99 (Honeypot DMZ)
- **Input**: REJECT
- **Output**: REJECT
- **Forward**: REJECT
- **Network**: 192.168.99.0/24
- **Isolation**: Strict isolation, see `../tpot-isolation/`

## Forwarding Matrix

| Source | Destination | Action | Notes |
|--------|-------------|--------|-------|
| **VLAN 10** | WAN | ALLOW | Full internet access |
| **VLAN 10** | VLAN 20 | ALLOW | Access to infrastructure |
| **VLAN 10** | VLAN 30 | DENY | No access to IoT/Guest |
| **VLAN 10** | VLAN 40 | ALLOW | Access to Lab VMs |
| **VLAN 10** | VLAN 99 | DENY | No access to Honeypot |
| **VLAN 20** | WAN | ALLOW | Full internet access |
| **VLAN 20** | All VLANs | ALLOW | Management network |
| **VLAN 30** | WAN | ALLOW | Internet only |
| **VLAN 30** | All other VLANs | DENY | Complete isolation |
| **VLAN 40** | WAN | ALLOW | Full internet access |
| **VLAN 40** | VLAN 20 | ALLOW | Access to infrastructure |
| **VLAN 40** | VLAN 10, 30, 99 | DENY | Isolated from other VLANs |
| **VLAN 99** | WAN | ALLOW | Internet access |
| **VLAN 99** | VLAN 20 | LIMITED | Only DNS (53) and Elasticsearch (9200) |
| **VLAN 99** | VLAN 10, 30, 40 | DENY | Complete isolation |

## Port Forwarding Rules

### WireGuard VPN (Port 51820)
```
WAN:51820 (UDP) → 192.168.20.1:51820 (OpenWrt)
```
- **Purpose**: VPN access to infrastructure
- **Destination**: Router itself
- **Protocol**: UDP

### Honeypot Services
All honeypot services forward to VLAN 99 (192.168.99.10):

| Service | WAN Port | Internal Port | Protocol |
|---------|----------|---------------|----------|
| SSH | 2222 | 22 | TCP |
| HTTP | 8080 | 80 | TCP |
| HTTPS | 8443 | 443 | TCP |
| FTP | 2121 | 21 | TCP |
| Telnet | 2323 | 23 | TCP |
| RDP | 3389 | 3389 | TCP |
| SMB | 4445 | 445 | TCP |

## Firewall Rules Detail

### 1. Default Policies

```bash
# WAN zone defaults
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Accept established/related connections
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

### 2. VLAN 10 → WAN (Internet Access)

```bash
# Allow VLAN 10 to WAN
iptables -A FORWARD -i br-vlan10 -o eth0 -j ACCEPT

# NAT for VLAN 10
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o eth0 -j MASQUERADE
```

### 3. VLAN 10 → VLAN 20 (Infrastructure Access)

```bash
# Allow VLAN 10 to VLAN 20
iptables -A FORWARD -i br-vlan10 -o br-vlan20 -j ACCEPT
iptables -A FORWARD -i br-vlan20 -o br-vlan10 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

### 4. VLAN 20 → All (Management Network)

```bash
# VLAN 20 can access everything
iptables -A FORWARD -i br-vlan20 -j ACCEPT
```

### 5. VLAN 30 Isolation (IoT/Guest)

```bash
# VLAN 30 → WAN only
iptables -A FORWARD -i br-vlan30 -o eth0 -j ACCEPT

# Block VLAN 30 → All internal VLANs
iptables -A FORWARD -i br-vlan30 -d 192.168.10.0/24 -j REJECT
iptables -A FORWARD -i br-vlan30 -d 192.168.20.0/24 -j REJECT
iptables -A FORWARD -i br-vlan30 -d 192.168.40.0/24 -j REJECT
iptables -A FORWARD -i br-vlan30 -d 192.168.99.0/24 -j REJECT

# NAT for VLAN 30
iptables -t nat -A POSTROUTING -s 192.168.30.0/24 -o eth0 -j MASQUERADE
```

### 6. VLAN 40 (Lab VMs)

```bash
# VLAN 40 → WAN
iptables -A FORWARD -i br-vlan40 -o eth0 -j ACCEPT

# VLAN 40 → VLAN 20
iptables -A FORWARD -i br-vlan40 -o br-vlan20 -j ACCEPT

# Block VLAN 40 → VLAN 10, 30, 99
iptables -A FORWARD -i br-vlan40 -d 192.168.10.0/24 -j REJECT
iptables -A FORWARD -i br-vlan40 -d 192.168.30.0/24 -j REJECT
iptables -A FORWARD -i br-vlan40 -d 192.168.99.0/24 -j REJECT

# NAT for VLAN 40
iptables -t nat -A POSTROUTING -s 192.168.40.0/24 -o eth0 -j MASQUERADE
```

### 7. VLAN 99 (Honeypot) - See ../tpot-isolation/

Detailed honeypot isolation rules are in `../tpot-isolation/firewall-honeypot`.

Key points:
- Allow VLAN 99 → WAN (internet)
- Allow VLAN 99 → 192.168.20.53:53 (DNS)
- Allow VLAN 99 → 192.168.20.10:9200 (Elasticsearch)
- Block everything else

### 8. Port Forwarding - WireGuard VPN

```bash
# Allow WireGuard on WAN
iptables -A INPUT -i eth0 -p udp --dport 51820 -j ACCEPT

# WireGuard traffic to VLAN 20
iptables -A FORWARD -i wg0 -o br-vlan20 -j ACCEPT
iptables -A FORWARD -i br-vlan20 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

### 9. Rate Limiting

```bash
# Limit SSH attempts (if SSH enabled on router)
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j REJECT

# Limit ICMP ping
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
```

### 10. Logging (Optional)

```bash
# Log dropped packets (limited)
iptables -A INPUT -m limit --limit 10/min -j LOG --log-prefix "IPT-INPUT-DROP: " --log-level 4
iptables -A FORWARD -m limit --limit 10/min -j LOG --log-prefix "IPT-FORWARD-DROP: " --log-level 4
```

## Security Features

### 1. SYN Flood Protection

```bash
iptables -A INPUT -p tcp --syn -m limit --limit 1/s -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP
```

### 2. Invalid Packet Drop

```bash
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
```

### 3. Fragmented Packet Drop

```bash
iptables -A INPUT -f -j DROP
iptables -A FORWARD -f -j DROP
```

### 4. Bogon/Private IP Block (WAN)

```bash
# Block private IPs from WAN
iptables -A INPUT -i eth0 -s 10.0.0.0/8 -j DROP
iptables -A INPUT -i eth0 -s 172.16.0.0/12 -j DROP
iptables -A INPUT -i eth0 -s 192.168.0.0/16 -j DROP
iptables -A INPUT -i eth0 -s 127.0.0.0/8 -j DROP
iptables -A INPUT -i eth0 -s 224.0.0.0/4 -j DROP
iptables -A INPUT -i eth0 -s 240.0.0.0/5 -j DROP
```

## Testing Firewall Rules

### Test VLAN Isolation

```bash
# From VLAN 10 device
ping 192.168.20.10  # Should work (Infrastructure)
ping 192.168.30.1   # Should fail (IoT isolated)
ping 192.168.99.10  # Should fail (Honeypot isolated)

# From VLAN 30 device (IoT)
ping 192.168.10.1   # Should fail
ping 192.168.20.10  # Should fail
ping 8.8.8.8        # Should work (Internet)

# From VLAN 99 (Honeypot)
ping 192.168.10.1   # Should fail
curl http://192.168.20.10:9200  # Should work (Elasticsearch)
dig @192.168.20.53 google.com   # Should work (DNS)
ping 8.8.8.8        # Should work (Internet)
```

### View Active Rules

```bash
# On OpenWrt router
iptables -L -n -v
iptables -t nat -L -n -v

# View specific chain
iptables -L FORWARD -n -v

# Count packets per rule
iptables -L -n -v --line-numbers
```

### Monitor Live Traffic

```bash
# Watch firewall logs
logread -f | grep -E "IPT|firewall"

# Monitor specific VLAN
tcpdump -i br-vlan10 -n

# Monitor forwarded traffic
tcpdump -i any -n 'ip[6] & 0x40 == 0'
```

## Troubleshooting

### Connection Blocked Unexpectedly

```bash
# Check if rule exists
iptables -L -n -v | grep <ip-address>

# Check NAT rules
iptables -t nat -L -n -v

# Enable logging temporarily
iptables -I FORWARD -s <source-ip> -j LOG --log-prefix "DEBUG: "

# Check logs
logread | grep "DEBUG:"
```

### Port Forward Not Working

```bash
# Check DNAT rule
iptables -t nat -L PREROUTING -n -v | grep <port>

# Check forward rule
iptables -L FORWARD -n -v | grep <destination-ip>

# Test from external network
nc -zv <public-ip> <port>
```

### Performance Issues

```bash
# Check connection tracking table
cat /proc/net/nf_conntrack | wc -l

# Check conntrack limit
sysctl net.netfilter.nf_conntrack_max

# Increase if needed
sysctl -w net.netfilter.nf_conntrack_max=65536
```

## Backup and Restore

### Backup Current Rules

```bash
# Save iptables rules
iptables-save > /tmp/iptables-backup.txt
scp /tmp/iptables-backup.txt user@192.168.20.10:/mnt/storage/backups/

# Backup UCI firewall config
tar -czf /tmp/firewall-config.tar.gz /etc/config/firewall
```

### Restore Rules

```bash
# Restore iptables rules (temporary until reboot)
iptables-restore < /tmp/iptables-backup.txt

# Restore UCI config
tar -xzf /tmp/firewall-config.tar.gz -C /
/etc/init.d/firewall restart
```

## Related Documentation

- [T-Pot Isolation](../tpot-isolation/README.md)
- [OpenWrt Configuration](../../network/openwrt/README.md)
- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- OpenWrt Firewall: https://openwrt.org/docs/guide-user/firewall/overview
