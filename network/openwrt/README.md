# OpenWrt Router Configuration

## Overview

The OpenWrt router is the perimeter device that provides:
- First line of defense (firewall)
- VLAN routing between networks
- WireGuard VPN endpoint
- DHCP and DNS services
- Port forwarding to T-Pot honeypot
- Logging to ELK Stack

## Quick Reference

**Management IPs**:
- VLAN 10: 192.168.10.1
- VLAN 20: 192.168.20.1 (preferred for management via VPN)
- VLAN 30: 192.168.30.1
- VLAN 40: 192.168.40.1
- VLAN 99: 192.168.99.1
- VPN: 10.10.100.1

**Access Methods**:
- Web UI: https://192.168.20.1 (via VPN recommended)
- SSH: `ssh root@192.168.20.1`
- Console: 115200 8N1

## Installation Steps

### 1. Initial OpenWrt Setup

If this is a fresh OpenWrt installation:

```bash
# Connect via SSH (default IP: 192.168.1.1)
ssh root@192.168.1.1

# Set root password
passwd

# Update package lists
opkg update

# Install required packages
opkg install luci luci-ssl wireguard-tools kmod-wireguard \
  ip-full kmod-8021q tcpdump iperf3 nano
```

### 2. Backup Existing Configuration

```bash
# Create backup of current config
sysupgrade -b /tmp/backup-$(date +%Y%m%d).tar.gz

# Download backup to your computer
scp root@192.168.1.1:/tmp/backup-*.tar.gz ~/
```

### 3. Apply Network Configuration

```bash
# SSH to router
ssh root@192.168.20.1

# Backup existing config
cp /etc/config/network /etc/config/network.bak

# Edit network config
nano /etc/config/network

# Copy contents from network-config file
# (paste the configuration)

# Restart network
/etc/init.d/network restart
```

**IMPORTANT**: After restarting network, you may lose connection. Reconnect to new IP.

### 4. Apply DHCP Configuration

```bash
# Backup existing config
cp /etc/config/dhcp /etc/config/dhcp.bak

# Edit DHCP config
nano /etc/config/dhcp

# Copy contents from dhcp-config file

# Restart dnsmasq
/etc/init.d/dnsmasq restart
```

### 5. Apply Firewall Configuration

```bash
# Backup existing config
cp /etc/config/firewall /etc/config/firewall.bak

# Edit firewall config
nano /etc/config/firewall

# Copy contents from firewall-config file

# Restart firewall
/etc/init.d/firewall restart
```

### 6. Configure WireGuard VPN

See [WireGuard Configuration](../../vpn/wireguard/README.md) for detailed setup.

```bash
# Generate server keys
umask 077
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key

# Edit network config and add private key
nano /etc/config/network
# Replace YOUR_PRIVATE_KEY_HERE with contents of server_private.key

# Restart network
/etc/init.d/network restart
```

### 7. Enable Logging to ELK

```bash
# Edit syslog configuration
nano /etc/config/system

# Add remote syslog server
config system
    option log_ip '192.168.20.20'
    option log_port '514'
    option log_proto 'udp'
    option log_remote '1'

# Restart syslog
/etc/init.d/log restart
```

### 8. Enable NetFlow/sFlow (optional)

```bash
# Install softflowd for NetFlow export
opkg install softflowd

# Configure softflowd
nano /etc/config/softflowd

config softflowd
    option enabled '1'
    option interface 'br-lan'
    option pcap_file ''
    option timeout 'maxlife=60'
    option max_flows '8192'
    option host_port '192.168.20.20:2055'
    option pid_file '/var/run/softflowd.pid'
    option control_socket '/var/run/softflowd.ctl'
    option export_version '9'
    option hoplimit ''
    option tracking_level 'full'
    option track_ipv6 '1'

# Start softflowd
/etc/init.d/softflowd enable
/etc/init.d/softflowd start
```

### 9. Verify Configuration

```bash
# Check network interfaces
ip addr show

# Check VLAN interfaces
ip -d link show

# Check routing table
ip route show

# Check firewall rules
iptables -L -v -n

# Check WireGuard status
wg show

# Check DHCP leases
cat /tmp/dhcp.leases

# Check system log
logread
```

## Maintenance

### Daily Checks

```bash
# Check system resources
top

# Check connections
netstat -an | grep ESTABLISHED | wc -l

# Check firewall log
logread | grep -i drop
```

### Weekly Maintenance

```bash
# Update package lists
opkg update

# Check for upgrades
opkg list-upgradable

# Upgrade packages (carefully!)
opkg upgrade <package>
```

### Monthly Maintenance

```bash
# Full system upgrade (test in lab first!)
sysupgrade -n <new-firmware.bin>

# Rotate WireGuard keys (recommended quarterly)
# See WireGuard documentation
```

## Troubleshooting

### No Internet Access

```bash
# Check WAN connection
ping -I eth0 8.8.8.8

# Check default route
ip route show

# Check NAT
iptables -t nat -L -v -n

# Restart network
/etc/init.d/network restart
```

### VLAN Not Working

```bash
# Check VLAN interfaces
ip -d link show | grep vlan

# Check if VLAN tagged correctly
cat /proc/net/vlan/config

# Test connectivity
ping -I eth1.10 192.168.10.100
```

### Firewall Blocking Traffic

```bash
# Check firewall rules
iptables -L -v -n | grep <port>

# Check firewall log
logread | grep firewall

# Temporarily disable firewall (testing only!)
/etc/init.d/firewall stop

# Re-enable
/etc/init.d/firewall start
```

### WireGuard VPN Not Working

```bash
# Check WireGuard status
wg show

# Check if port is open
netstat -ulnp | grep 51820

# Check WireGuard logs
logread | grep wireguard

# Test from outside (from VPN client)
# Try to connect and check logs
```

### DHCP Not Working

```bash
# Check dnsmasq status
/etc/init.d/dnsmasq status

# Check dnsmasq log
logread | grep dnsmasq

# Check DHCP leases
cat /tmp/dhcp.leases

# Restart dnsmasq
/etc/init.d/dnsmasq restart
```

### High CPU Usage

```bash
# Check top processes
top

# Common culprits:
# - uhttpd (web server)
# - dnsmasq (DNS/DHCP)
# - firewall (too many rules)

# Check connections
netstat -an | wc -l
```

## Security Hardening

### Change Default Passwords

```bash
# Change root password
passwd

# Use strong password (16+ characters, mixed case, numbers, symbols)
```

### Disable Unused Services

```bash
# Disable UPnP (if not needed)
/etc/init.d/miniupnpd stop
/etc/init.d/miniupnpd disable

# Disable IPv6 (if not used)
# Edit /etc/config/network and disable ipv6
```

### Enable HTTPS Only

```bash
# Disable HTTP access
uci set uhttpd.main.listen_http='0'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

### Restrict SSH Access

```bash
# Edit SSH config
nano /etc/config/dropbear

config dropbear
    option PasswordAuth 'off'  # Use key-based auth only
    option RootPasswordAuth 'off'
    option Port '22'
    option Interface '192.168.20.1'  # Listen only on Infrastructure VLAN

# Restart SSH
/etc/init.d/dropbear restart
```

### Enable Fail2Ban (optional)

```bash
# Install fail2ban
opkg install fail2ban

# Configure for SSH protection
# Edit /etc/fail2ban/jail.local
```

## Performance Tuning

### For 120 Mbit/s Connection

```bash
# Increase conntrack table size
sysctl -w net.netfilter.nf_conntrack_max=32768

# Make permanent
echo "net.netfilter.nf_conntrack_max=32768" >> /etc/sysctl.conf
```

### For High Traffic VLANs

```bash
# Increase buffer sizes
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728

# Make permanent
echo "net.core.rmem_max=134217728" >> /etc/sysctl.conf
echo "net.core.wmem_max=134217728" >> /etc/sysctl.conf
```

## Backup & Restore

### Manual Backup

```bash
# Backup all configs
tar -czf /tmp/openwrt-backup-$(date +%Y%m%d).tar.gz /etc/config/

# Download
scp root@192.168.20.1:/tmp/openwrt-backup-*.tar.gz ~/
```

### Automated Backup

Add to crontab on CentOS server:

```bash
0 2 * * * /opt/homesec/scripts/backup-openwrt-config.sh
```

### Restore Configuration

```bash
# Upload backup
scp ~/openwrt-backup-*.tar.gz root@192.168.20.1:/tmp/

# Extract
cd /
tar -xzf /tmp/openwrt-backup-*.tar.gz

# Reload services
/etc/init.d/network reload
/etc/init.d/firewall reload
/etc/init.d/dnsmasq reload
```

## Monitoring

### Key Metrics to Monitor

- **CPU Usage**: Should be < 50% average
- **Memory Usage**: Should be < 80%
- **WAN Bandwidth**: Monitor for anomalies
- **Firewall Drops**: Sudden spikes indicate attacks
- **VPN Connections**: Monitor active clients
- **Uptime**: Track stability

### Integration with ELK

All logs are sent to Rock Pi 4 SE (192.168.20.20) which forwards to ELK Stack.

**Log sources**:
- Firewall drops/rejects
- DHCP assignments
- WireGuard connections
- System errors
- Security events

## Related Documentation

- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- [WireGuard VPN](../../vpn/wireguard/README.md)
- [Firewall Rules](../../firewall/openwrt-rules/README.md)

## Useful Commands Reference

```bash
# Network
ip addr show              # Show all IPs
ip route show             # Show routing table
ip -d link show           # Show VLANs
brctl show                # Show bridges

# Firewall
iptables -L -v -n         # Show filter table
iptables -t nat -L -v -n  # Show NAT table
fw3 reload                # Reload firewall

# Services
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
/etc/init.d/dropbear restart

# Logs
logread                   # View system log
logread -f                # Follow log
logread | grep firewall   # Filter log

# WireGuard
wg show                   # Show VPN status
wg genkey                 # Generate key
wg pubkey                 # Derive public key

# System
uci show                  # Show all config
uci commit                # Commit changes
sysupgrade -n <file>      # Upgrade firmware
reboot                    # Reboot router
```

## Support Resources

- OpenWrt Wiki: https://openwrt.org/docs/start
- OpenWrt Forum: https://forum.openwrt.org/
- WireGuard Docs: https://www.wireguard.com/
