# T-Pot Honeypot Isolation

## Overview

This directory contains firewall rules and configuration for T-Pot honeypot isolation on VLAN 99. The honeypot must be completely isolated from internal networks while maintaining internet access and logging capability.

**Purpose**: Prevent compromised honeypot from attacking internal infrastructure
**VLAN**: 99 (192.168.99.0/24)
**Honeypot IP**: 192.168.99.10

## Isolation Requirements

### Allowed Connections FROM Honeypot

| Destination | Port | Protocol | Purpose |
|-------------|------|----------|---------|
| Internet (any) | Any | Any | Allow all outbound to internet |
| 192.168.20.10 | 9200 | TCP | Elasticsearch logging |
| 192.168.20.53 | 53 | UDP | DNS queries |
| 192.168.20.1 | Any | ICMP | Gateway ping (monitoring) |

### Blocked Connections FROM Honeypot

- **All other internal VLANs** (10, 20, 30, 40)
- **Honeypot cannot initiate connections to internal resources**
- **Exception**: DNS and Elasticsearch only

### Allowed Connections TO Honeypot

| Source | Port | Protocol | Purpose |
|--------|------|----------|---------|
| Internet | 22 (→2222) | TCP | SSH honeypot |
| Internet | 80 (→8080) | TCP | HTTP honeypot |
| Internet | 443 (→8443) | TCP | HTTPS honeypot |
| Internet | 21 (→2121) | TCP | FTP honeypot |
| Internet | 23 (→2323) | TCP | Telnet honeypot |
| Internet | 3389 (→3389) | TCP | RDP honeypot |
| Internet | 445 (→4445) | TCP | SMB honeypot |
| VLAN 20 only | 64297 | TCP | T-Pot Web UI (via VPN) |

## OpenWrt Firewall Configuration

### Zone Configuration

```bash
# VLAN 99 Zone - Honeypot DMZ
config zone
    option name 'honeypot'
    option input 'REJECT'
    option output 'REJECT'
    option forward 'REJECT'
    option network 'vlan99'
    option masq '1'
    option log '1'
    option log_limit '10/minute'
```

### Forwarding Rules

```bash
# Allow honeypot to internet (WAN)
config forwarding
    option src 'honeypot'
    option dest 'wan'

# Block all other forwarding
# (No forwarding to lan, vlan10, vlan20, vlan30, vlan40)
```

### Specific Allow Rules

```bash
# Allow DNS to internal DNS server
config rule
    option name 'Honeypot-DNS'
    option src 'honeypot'
    option dest 'vlan20'
    option dest_ip '192.168.20.53'
    option dest_port '53'
    option proto 'udp'
    option target 'ACCEPT'

# Allow Elasticsearch logging
config rule
    option name 'Honeypot-Elasticsearch'
    option src 'honeypot'
    option dest 'vlan20'
    option dest_ip '192.168.20.10'
    option dest_port '9200'
    option proto 'tcp'
    option target 'ACCEPT'

# Allow ICMP to gateway (for monitoring)
config rule
    option name 'Honeypot-Ping-Gateway'
    option src 'honeypot'
    option dest_ip '192.168.20.1'
    option proto 'icmp'
    option icmp_type 'echo-request'
    option target 'ACCEPT'
```

### Port Forwarding from Internet

```bash
# SSH Honeypot
config redirect
    option name 'SSH-Honeypot'
    option src 'wan'
    option src_dport '2222'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '22'
    option proto 'tcp'
    option target 'DNAT'

# HTTP Honeypot
config redirect
    option name 'HTTP-Honeypot'
    option src 'wan'
    option src_dport '8080'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '80'
    option proto 'tcp'
    option target 'DNAT'

# HTTPS Honeypot
config redirect
    option name 'HTTPS-Honeypot'
    option src 'wan'
    option src_dport '8443'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '443'
    option proto 'tcp'
    option target 'DNAT'

# FTP Honeypot
config redirect
    option name 'FTP-Honeypot'
    option src 'wan'
    option src_dport '2121'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '21'
    option proto 'tcp'
    option target 'DNAT'

# Telnet Honeypot
config redirect
    option name 'Telnet-Honeypot'
    option src 'wan'
    option src_dport '2323'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '23'
    option proto 'tcp'
    option target 'DNAT'

# RDP Honeypot
config redirect
    option name 'RDP-Honeypot'
    option src 'wan'
    option src_dport '3389'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '3389'
    option proto 'tcp'
    option target 'DNAT'

# SMB Honeypot
config redirect
    option name 'SMB-Honeypot'
    option src 'wan'
    option src_dport '4445'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '445'
    option proto 'tcp'
    option target 'DNAT'
```

### T-Pot Web UI Access (VLAN 20 Only)

```bash
# Allow T-Pot Web UI from VLAN 20 (Infrastructure)
config rule
    option name 'TPot-WebUI'
    option src 'vlan20'
    option dest 'honeypot'
    option dest_ip '192.168.99.10'
    option dest_port '64297'
    option proto 'tcp'
    option target 'ACCEPT'
    option enabled '1'
```

## Testing Isolation

### Test 1: Verify Honeypot Cannot Reach Internal Networks

```bash
# From honeypot VM:
ping 192.168.10.100   # Should FAIL
ping 192.168.20.10    # Should FAIL (except Elasticsearch port)
ping 192.168.30.100   # Should FAIL
ping 192.168.40.100   # Should FAIL

# Test Elasticsearch (should work)
curl http://192.168.20.10:9200  # Should SUCCEED

# Test DNS (should work)
dig @192.168.20.53 google.com   # Should SUCCEED
```

### Test 2: Verify Internet Access

```bash
# From honeypot VM:
ping 8.8.8.8          # Should SUCCEED
curl http://google.com  # Should SUCCEED
curl https://google.com # Should SUCCEED
```

### Test 3: Verify Port Forwarding

```bash
# From external network (or via mobile connection):
ssh -p 2222 <public-ip>    # Should reach honeypot SSH
curl http://<public-ip>:8080  # Should reach honeypot HTTP
```

### Test 4: Verify Web UI Access

```bash
# From VPN client (connected to VLAN 20):
curl https://192.168.99.10:64297  # Should SUCCEED

# From other VLANs:
# Should FAIL
```

## Monitoring

### View Blocked Attempts

On OpenWrt router:

```bash
# View firewall log
logread | grep REJECT

# View specific honeypot blocks
logread | grep "192.168.99"

# Count blocked attempts
logread | grep "192.168.99" | grep REJECT | wc -l
```

### Monitor in Kibana

Create dashboard to monitor:
- Honeypot outbound connection attempts (blocked)
- Honeypot inbound attacks from internet
- DNS queries from honeypot
- Elasticsearch log submissions from honeypot

Query examples:
```
# Blocked honeypot outbound
source_ip:192.168.99.10 AND action:REJECT

# Honeypot DNS queries
source_ip:192.168.99.10 AND dest_port:53

# Attacks on honeypot
dest_ip:192.168.99.10 AND source_ip:NOT(192.168.*)
```

## Security Considerations

1. **Complete Isolation**: Honeypot must NEVER access internal networks
2. **Logging Only**: Only allow Elasticsearch for logging, nothing else
3. **No SSH from Internal**: Do not SSH to honeypot from internal networks
4. **Monitor Elasticsearch Traffic**: Watch for data exfiltration attempts via ES
5. **Regular Updates**: Update honeypot OS and T-Pot regularly (via internet)
6. **Separate Credentials**: Never use production credentials in honeypot

## Troubleshooting

### Honeypot Cannot Log to Elasticsearch

```bash
# Check firewall rule
uci show firewall | grep -A 5 "Honeypot-Elasticsearch"

# Test from honeypot
curl -v http://192.168.20.10:9200

# Check OpenWrt logs
logread | grep "192.168.99.10.*192.168.20.10.*9200"
```

### Port Forwarding Not Working

```bash
# Check NAT rules
iptables -t nat -L -n -v | grep 2222

# Test from external network
nc -zv <public-ip> 2222

# Check OpenWrt firewall
uci show firewall | grep -A 5 "SSH-Honeypot"
```

### Honeypot Can Access Internal Networks (BAD!)

```bash
# Review firewall configuration
uci show firewall

# Check forwarding rules
iptables -L FORWARD -n -v | grep 192.168.99

# Verify no unintended rules
grep -r "192.168.99" /etc/config/
```

## Emergency Response

If honeypot is compromised and attacking internal networks:

```bash
# Immediately block all honeypot traffic
iptables -I FORWARD -s 192.168.99.0/24 -j DROP
iptables -I FORWARD -d 192.168.99.0/24 -j DROP

# Or shutdown honeypot VM
# On server: virsh shutdown tpot-vm

# Investigate logs
# Check Elasticsearch for attack indicators
```

## Related Documentation

- [OpenWrt Firewall Configuration](../../network/openwrt/README.md)
- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- T-Pot Documentation: https://github.com/telekom-security/tpotce
