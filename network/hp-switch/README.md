# HP 2530-24G-PoEP Switch Configuration

## Overview

The HP 2530-24G-PoEP (J9773A) is the network core of HomeSec, providing:
- VLAN segmentation (5 VLANs)
- Port mirroring (SPAN) to IDS
- PoE for WiFi access points
- sFlow network monitoring
- SNMP monitoring

## Quick Reference

**Management IP**: 192.168.20.11 (VLAN 20)
**Default Gateway**: 192.168.20.1
**DNS**: 192.168.20.53

**Access Methods**:
- Web UI: https://192.168.20.11 (via VPN or VLAN 20)
- SSH: `ssh manager@192.168.20.11`
- Console: 9600 8N1

## Port Assignment

| Port(s) | VLAN | Usage | PoE |
|---------|------|-------|-----|
| 1-8 | 10 | Trusted LAN devices | No |
| 9 | 20 | CentOS Server (trunk) | No |
| 10 | 20 | Rock Pi 4 SE (IDS) | No |
| 11-16 | 30 | WiFi APs (6x) | Yes |
| 17-20 | 10 | Trusted LAN devices | No |
| 21 | Trunk | Uplink to Rock Pi E | No |
| 22 | SPAN | Mirror to IDS (Rock Pi 4 SE) | No |
| 23-24 | 20 | Management/Reserved | No |

## Installation Steps

### 1. Initial Setup via Console

Connect via console cable (9600 8N1):

```
# Login with default credentials
Username: manager
Password: (default or set during first boot)

# Enter configuration mode
configure

# Set hostname
hostname "HomeSec-Switch"

# Set management IP
vlan 20
ip address 192.168.20.11 255.255.255.0
exit

ip default-gateway 192.168.20.1

# Save config
write memory
```

### 2. Apply Full Configuration

1. **Backup existing config** (if any):
   ```
   copy running-config tftp 192.168.20.10 hp2530-backup-old.cfg
   ```

2. **Copy configuration** from `hp2530-config.txt`
   - Open console session
   - Copy sections from config file
   - Paste into console (may need to do in sections)

3. **Verify configuration**:
   ```
   show running-config
   show vlan
   show interfaces brief
   show mirror
   ```

4. **Save configuration**:
   ```
   write memory
   ```

### 3. Enable Management Access

```
# Enable HTTPS management
web-management ssl

# Enable SSH
ip ssh

# Disable insecure protocols
no telnet-server
no web-management plaintext
```

### 4. Verify VLAN Configuration

```
show vlan

# Expected output:
# VLAN 10: Ports 1-8, 17-20 (untagged)
# VLAN 20: Ports 9-10, 23-24 (untagged), Port 21 (tagged)
# VLAN 30: Ports 11-16 (untagged)
# VLAN 40: Port 21 (tagged)
# VLAN 99: Port 21 (tagged)
```

### 5. Verify Port Mirroring

```
show mirror

# Expected output:
# Mirror 1 (IDS-Monitor):
#   Source ports: 1-21, 23-24
#   Destination: 22
#   Direction: both
```

### 6. Verify PoE

```
show power-over-ethernet brief

# Verify ports 11-16 have PoE enabled
```

## Configuration Backup

### Manual Backup (via TFTP)

```
copy running-config tftp 192.168.20.10 hp2530-config-backup.cfg
```

### Automated Backup

Use the backup script on CentOS server:
```bash
/opt/homesec/scripts/backup-switch-config.sh
```

This runs daily via cron and stores configs in `/mnt/raid/backups/network/`.

## Monitoring

### SNMP

The switch exports SNMP data to Rock Pi 4 SE (192.168.20.20).

**Community**: public (change in production!)

**Polled metrics**:
- Interface statistics
- Port status
- PoE usage
- System health

### sFlow

The switch exports sFlow data to Rock Pi 4 SE (192.168.20.20).

**Sample rate**: 1:512 packets
**Polling interval**: 30 seconds

### Syslog

Logs are sent to Rock Pi 4 SE (192.168.20.20) and forwarded to ELK Stack.

## Troubleshooting

### Port Not Working

```
show interfaces <port>

# Check if port is:
# - Enabled
# - Correct VLAN
# - Link detected
# - Errors/drops
```

### VLAN Issues

```
show vlan <vlan-id>

# Verify:
# - Correct ports assigned
# - Tagged vs untagged
```

### Port Mirroring Not Working

```
show mirror

# Verify:
# - Source ports correct
# - Destination port correct
# - Direction is "both"

# Test on Rock Pi 4 SE:
sudo tcpdump -i eth0 -c 100
# Should see mirrored traffic
```

### PoE Not Working

```
show power-over-ethernet interface <port>

# Check:
# - PoE enabled on port
# - Power budget available
# - Device is PoE compatible
```

### No Management Access

1. **Via Console**:
   ```
   show ip
   show vlan 20
   ping 192.168.20.1
   ```

2. **Check firewall rules** on OpenWrt router

3. **Verify VLAN 20** is correctly configured

### Switch Not Responding

1. **Reboot**:
   ```
   reload
   ```

2. **Factory reset** (last resort):
   - Hold CLEAR button for 10 seconds during boot
   - Reconfigure from scratch

## Security Best Practices

1. **Change default password** immediately
2. **Disable unused protocols**:
   ```
   no telnet-server
   no tftp server
   no web-management plaintext
   ```
3. **Use strong SNMP community** (not "public")
4. **Enable port security** on user-facing ports
5. **Disable unused ports**:
   ```
   interface <port>
   disable
   exit
   ```

## Firmware Updates

1. **Check current firmware**:
   ```
   show version
   ```

2. **Download latest firmware** from HP website

3. **Upload via TFTP**:
   ```
   copy tftp flash 192.168.20.10 <firmware-file>.swi primary
   ```

4. **Reboot**:
   ```
   boot system flash primary
   reload
   ```

## Useful Commands

```bash
# Show running config
show running-config

# Show specific VLAN
show vlan 10

# Show interface status
show interfaces brief

# Show MAC address table
show mac-address

# Show PoE status
show power-over-ethernet brief

# Show system info
show system

# Show logs
show logging

# Clear MAC address table
clear mac-address-table

# Reload switch
reload

# Save config
write memory
```

## Related Documentation

- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- [OpenWrt Configuration](../openwrt/README.md)

## Support

For HP 2530 documentation, visit:
https://support.hpe.com/connect/s/product?language=en_US&ismnumber=J9773A
