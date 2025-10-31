# HomeSec - Network Design

## IP Addressing Plan

### Subnets Overview

| VLAN | Name | Subnet | Gateway | DHCP Range | Description |
|------|------|--------|---------|------------|-------------|
| 1 | WAN | ISP assigned | ISP | N/A | Internet connection |
| 10 | Trusted LAN | 192.168.10.0/24 | .1 | .100-.250 | Trusted devices |
| 20 | Infrastructure | 192.168.20.0/24 | .1 | .100-.150 | Servers, management |
| 30 | IoT/Guest | 192.168.30.0/24 | .1 | .100-.250 | IoT devices, guests |
| 40 | Lab | 192.168.40.0/24 | .1 | .100-.200 | Virtual machines |
| 99 | Honeypot DMZ | 192.168.99.0/24 | .1 | N/A | T-Pot (static IP) |
| 100 | VPN Clients | 10.10.100.0/24 | N/A | N/A | WireGuard VPN |

## Static IP Assignments

### VLAN 10 - Trusted LAN
| IP | Device | Description |
|----|--------|-------------|
| 192.168.10.1 | OpenWrt Router | Default gateway |
| 192.168.10.100-250 | DHCP Pool | Trusted devices |

### VLAN 20 - Infrastructure
| IP | Device | Description |
|----|--------|-------------|
| 192.168.20.1 | OpenWrt Router | Gateway |
| 192.168.20.10 | CentOS Server | Main server |
| 192.168.20.11 | HP 2530 Switch | Management interface |
| 192.168.20.20 | Rock Pi 4 SE | IDS + Collectors |
| 192.168.20.53 | CentOS Server | DNS (BIND) |
| 192.168.20.100-150 | DHCP Pool | Additional infrastructure |

### VLAN 30 - IoT/Guest
| IP | Device | Description |
|----|--------|-------------|
| 192.168.30.1 | OpenWrt Router | Gateway |
| 192.168.30.10-19 | WiFi APs | 6x Access Points (static) |
| 192.168.30.100-250 | DHCP Pool | IoT devices, guests |

### VLAN 40 - Lab
| IP | Device | Description |
|----|--------|-------------|
| 192.168.40.1 | OpenWrt Router | Gateway |
| 192.168.40.10 | Windows Server 2019 | Lab VM |
| 192.168.40.11 | Windows 11 | Lab VM |
| 192.168.40.100-200 | DHCP Pool | Additional lab VMs |

### VLAN 99 - Honeypot DMZ
| IP | Device | Description |
|----|--------|-------------|
| 192.168.99.1 | OpenWrt Router | Gateway |
| 192.168.99.10 | T-Pot VM | Honeypot suite (Alma Linux) |

### VPN Network (WireGuard)
| IP | Device | Description |
|----|--------|-------------|
| 10.10.100.1 | OpenWrt Router | WireGuard server |
| 10.10.100.2-50 | VPN Clients | Remote devices |

## Physical Network Topology

```
    [Internet] (ISP assigned IP)
        |
        |
    [OpenWrt Router] (192.168.x.1 on all VLANs)
        | eth1 (to Rock Pi E)
        |
    [Rock Pi E - IPS Bridge]
        | eth0: WAN side (from router)
        | eth1: LAN side (to switch)
        |
    [HP 2530-24G Switch] (192.168.20.11)
        | VLAN tagging
        | Port mirroring (SPAN)
        |
        +--- Port 1-8: VLAN 10 (Trusted) - Desktops, laptops
        +--- Port 9: VLAN 20 (Infrastructure) - CentOS Server (192.168.20.10)
        +--- Port 10: VLAN 20 - Rock Pi 4 SE (192.168.20.20)
        +--- Port 11-16: VLAN 30 (IoT/Guest) - 6x WiFi APs
        +--- Port 17-20: VLAN 10 (Trusted) - Additional devices
        +--- Port 21: Trunk - Uplink till Rock Pi E (all VLANs)
        +--- Port 22: SPAN/Mirror - Port mirroring till Rock Pi 4 SE
        +--- Port 23: VLAN 20 - Management/Reserved
        +--- Port 24: VLAN 20 - Reserved
```

## VLAN Configuration

### VLAN Tagging (802.1Q)

**Trunk Ports** (all VLANs):
- Port 21: Uplink från Rock Pi E
- Port 9: Server (with VLAN tagging on NIC)

**Access Ports**:
- Port 1-8, 17-20: VLAN 10 (untagged)
- Port 10, 23-24: VLAN 20 (untagged)
- Port 11-16: VLAN 30 (untagged)

**SPAN Port**:
- Port 22: Mirror all traffic → Rock Pi 4 SE

### Inter-VLAN Routing

Routing mellan VLANs hanteras av OpenWrt Router.

**Allowed Traffic**:
```
VLAN 10 (Trusted) → VLAN 20 (Infrastructure): YES (DNS, NAS, Kibana)
VLAN 10 (Trusted) → VLAN 30 (IoT/Guest): NO
VLAN 10 (Trusted) → VLAN 40 (Lab): NO
VLAN 10 (Trusted) → VLAN 99 (Honeypot): NO

VLAN 20 (Infrastructure) → ALL VLANs: YES (management)

VLAN 30 (IoT/Guest) → VLAN 10, 20, 40, 99: NO
VLAN 30 (IoT/Guest) → Internet: YES

VLAN 40 (Lab) → VLAN 20 (Infrastructure): YES (DNS)
VLAN 40 (Lab) → VLAN 10, 30, 99: NO

VLAN 99 (Honeypot) → Internet: YES (log shipping)
VLAN 99 (Honeypot) → VLAN 20: YES (only Elasticsearch:9200)
VLAN 99 (Honeypot) → ALL other VLANs: NO

VPN (10.10.100.0/24) → VLAN 20: YES (management only)
VPN (10.10.100.0/24) → VLAN 10, 30, 40, 99: NO (security)
```

## Firewall Rules (OpenWrt)

### Zone Configuration

```
Zone: WAN
  - Input: REJECT
  - Output: ACCEPT
  - Forward: REJECT

Zone: LAN_TRUSTED (VLAN 10)
  - Input: ACCEPT
  - Output: ACCEPT
  - Forward: REJECT (with exceptions)

Zone: INFRASTRUCTURE (VLAN 20)
  - Input: ACCEPT
  - Output: ACCEPT
  - Forward: ACCEPT (management can reach all)

Zone: IOT_GUEST (VLAN 30)
  - Input: REJECT
  - Output: ACCEPT
  - Forward: REJECT (isolated)

Zone: LAB (VLAN 40)
  - Input: ACCEPT
  - Output: ACCEPT
  - Forward: REJECT (with exceptions)

Zone: HONEYPOT_DMZ (VLAN 99)
  - Input: REJECT
  - Output: ACCEPT (restricted)
  - Forward: REJECT

Zone: VPN
  - Input: ACCEPT
  - Output: ACCEPT
  - Forward: REJECT (only to VLAN 20)
```

### Forwarding Rules

```
# Trusted LAN → Infrastructure (DNS, NAS, Kibana)
LAN_TRUSTED → INFRASTRUCTURE
  - Allow: DNS (53/tcp, 53/udp) to 192.168.20.53
  - Allow: HTTPS (443/tcp) to 192.168.20.10 (Kibana)
  - Allow: Samba (445/tcp) to 192.168.20.10 (NAS)
  - Allow: NFS (2049/tcp) to 192.168.20.10 (NAS)

# Infrastructure → All (management)
INFRASTRUCTURE → ALL
  - Allow: ALL

# IoT/Guest → Internet only
IOT_GUEST → WAN
  - Allow: ALL

# Lab → DNS
LAB → INFRASTRUCTURE
  - Allow: DNS (53/tcp, 53/udp) to 192.168.20.53

# Honeypot → Elasticsearch only
HONEYPOT_DMZ → INFRASTRUCTURE
  - Allow: HTTPS (9200/tcp) to 192.168.20.10 (Elasticsearch)
  - Drop: ALL other traffic

# VPN → Infrastructure management
VPN → INFRASTRUCTURE
  - Allow: SSH (22/tcp) to 192.168.20.10
  - Allow: HTTPS (443/tcp) to 192.168.20.10 (Kibana)
  - Allow: HTTP (80/tcp) to 192.168.20.11 (Switch web UI)
  - Allow: HTTPS (443/tcp) to 192.168.20.11 (Switch web UI)
  - Allow: DNS (53/tcp, 53/udp) to 192.168.20.53

# Internet → Honeypot (limited ports)
WAN → HONEYPOT_DMZ
  - Allow: 21/tcp (FTP honeypot)
  - Allow: 22/tcp (SSH honeypot)
  - Allow: 23/tcp (Telnet honeypot)
  - Allow: 80/tcp (HTTP honeypot)
  - Allow: 443/tcp (HTTPS honeypot)
  - Allow: 3306/tcp (MySQL honeypot)
  - Allow: 5432/tcp (PostgreSQL honeypot)
  - Allow: 1433/tcp (MSSQL honeypot)
  - Drop: ALL other traffic

# WireGuard VPN access
WAN → Router
  - Allow: 51820/udp (WireGuard)
```

## DNS Configuration

### Primary DNS: BIND on CentOS (192.168.20.53)

**Forwarders**:
- Cloudflare: 1.1.1.1, 1.0.0.1
- Google: 8.8.8.8, 8.8.4.4

**Local DNS Records**:
```
# Infrastructure
server.homesec.local       → 192.168.20.10
dns.homesec.local          → 192.168.20.53
nas.homesec.local          → 192.168.20.10
kibana.homesec.local       → 192.168.20.10
elk.homesec.local          → 192.168.20.10
switch.homesec.local       → 192.168.20.11
router.homesec.local       → 192.168.20.1

# Security devices
ids.homesec.local          → 192.168.20.20  (Rock Pi 4 SE)
ips.homesec.local          → (bridge, no IP)

# VMs
tpot.homesec.local         → 192.168.99.10
win2019.homesec.local      → 192.168.40.10
win11.homesec.local        → 192.168.40.11

# WiFi APs
ap1.homesec.local          → 192.168.30.10
ap2.homesec.local          → 192.168.30.11
ap3.homesec.local          → 192.168.30.12
ap4.homesec.local          → 192.168.30.13
ap5.homesec.local          → 192.168.30.14
ap6.homesec.local          → 192.168.30.15
```

**DHCP DNS Assignment**:
- All VLANs get 192.168.20.53 as primary DNS
- Secondary DNS: 1.1.1.1 (Cloudflare)

## WiFi Configuration

### SSIDs

**SSID 1: "HomeSec-Trusted"**
- Security: WPA3-Personal (fallback WPA2)
- Password: (Strong passphrase)
- VLAN: 10 (Trusted LAN)
- Client Isolation: Disabled
- Hidden: No

**SSID 2: "HomeSec-IoT"**
- Security: WPA2-Personal
- Password: (Separate passphrase)
- VLAN: 30 (IoT/Guest)
- Client Isolation: Enabled
- Hidden: No

**SSID 3: "HomeSec-Guest"**
- Security: WPA2-Personal
- Password: (Shared with guests)
- VLAN: 30 (IoT/Guest)
- Client Isolation: Enabled
- Hidden: No
- Captive Portal: Optional

### Access Point Placement
- **AP1 (UPS)**: Living room
- **AP2 (UPS)**: Office/Server room
- **AP3 (UPS)**: Master bedroom
- **AP4**: Kitchen
- **AP5**: Garage
- **AP6**: Basement

## Port Mirroring (SPAN)

### HP 2530 Switch Configuration

**Source Ports**: ALL ports (1-21, 23-24)
**Destination Port**: Port 22 (Rock Pi 4 SE)
**Direction**: Both (Ingress + Egress)

This sends a copy of all traffic to Rock Pi 4 SE for passive IDS analysis.

## QoS (Optional)

### Traffic Prioritization
1. **High Priority**: DNS, VPN, SSH
2. **Medium Priority**: HTTPS, HTTP
3. **Low Priority**: Bulk transfers, P2P

### Bandwidth Limits per VLAN
- VLAN 10 (Trusted): 80% of 120 Mbit/s = 96 Mbit/s
- VLAN 20 (Infrastructure): No limit
- VLAN 30 (IoT/Guest): 30% of 120 Mbit/s = 36 Mbit/s
- VLAN 40 (Lab): 20% of 120 Mbit/s = 24 Mbit/s
- VLAN 99 (Honeypot): 10% of 120 Mbit/s = 12 Mbit/s

## Network Monitoring

### Data Collection Points

1. **OpenWrt Router**
   - NetFlow/sFlow export → Rock Pi 4 SE
   - Firewall logs → Syslog → Rock Pi 4 SE → ELK
   - WireGuard logs → Syslog → ELK

2. **HP 2530 Switch**
   - SNMP polling from Rock Pi 4 SE (Metricbeat)
   - sFlow export → Rock Pi 4 SE
   - Syslog → Rock Pi 4 SE → ELK

3. **Rock Pi E (IPS)**
   - Suricata alerts → ELK
   - System metrics → ELK

4. **Rock Pi 4 SE (IDS)**
   - Suricata alerts → ELK
   - NetFlow/sFlow collector
   - System metrics → ELK

5. **WiFi APs**
   - SNMP polling → Rock Pi 4 SE
   - Syslog → Rock Pi 4 SE → ELK

6. **CentOS Server**
   - System metrics → ELK
   - BIND DNS logs → ELK
   - NAS access logs → ELK
   - VM metrics → ELK
   - RAID status → ELK

7. **T-Pot VM**
   - Honeypot logs → ELK
   - Attack data → ELK

## MTU Considerations

### Standard MTU: 1500 bytes

**Devices**:
- All VLANs: 1500
- VPN (WireGuard): 1420 (overhead for encapsulation)

**Rock Pi E Bridge**: MTU 1500 (no reduction)

## Network Testing

### Throughput Test
```bash
# Test 1: Without IPS (bypass Rock Pi E)
iperf3 -c <server> -t 60 -i 5

# Test 2: With IPS (through Rock Pi E)
iperf3 -c <server> -t 60 -i 5

# Expected: < 5% throughput reduction at 120 Mbit/s
```

### Latency Test
```bash
# Test 1: Ping without IPS
ping -c 100 8.8.8.8

# Test 2: Ping with IPS
ping -c 100 8.8.8.8

# Expected: < 5ms additional latency
```

### VLAN Isolation Test
```bash
# From VLAN 30 (IoT), try to reach VLAN 10 (Trusted)
ping 192.168.10.100
# Expected: Destination unreachable

# From VLAN 10 (Trusted), try to reach Kibana
curl https://kibana.homesec.local
# Expected: Success
```

## Backup Network Configuration

All network configs should be backed up:
- OpenWrt: `/etc/config/`
- HP Switch: Running config (via TFTP)
- BIND: `/etc/named/`
- Firewall rules: `/etc/firewall.user`

Backup location: `/mnt/raid/backups/network-configs/`

## Future Expansion

### If bandwidth increases to 500+ Mbit/s:
- Upgrade Rock Pi E to more powerful device (or multiple IPS instances)
- Consider hardware-accelerated IPS (FPGA-based)

### If more VLANs needed:
- VLAN 50: Cameras/Surveillance
- VLAN 60: Home Automation
- VLAN 70: Work-from-home (isolated)

### If more advanced routing needed:
- BGP for multi-WAN
- VRF for advanced isolation
- SD-WAN for traffic optimization
