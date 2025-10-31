# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HomeSec is a home IDS/IPS (Intrusion Detection/Prevention System) with centralized logging, visualization, and monitoring. It's a multi-device infrastructure project combining network security appliances, not a traditional software development project.

**Key characteristics:**
- Infrastructure-as-Code approach (configuration files, not application code)
- Multi-device deployment (routers, switches, ARM boards, server VMs)
- Focus on network security monitoring and threat detection
- Swedish documentation with English technical configs

## Architecture at a Glance

```
Internet → OpenWrt Router (firewall)
    → Rock Pi E (IPS inline bridge - blocks threats)
    → HP Switch (VLAN segmentation + SPAN port)
        ├─ Rock Pi 4 SE (IDS passive + data collectors)
        ├─ CentOS Server (ELK Stack + VMs + NAS)
        └─ 6x WiFi APs
```

**Data flow:** All logs → Filebeat → Elasticsearch → Kibana dashboards

**Security layers:**
1. OpenWrt firewall (perimeter)
2. Rock Pi E IPS (inline blocking)
3. VLAN isolation (5 VLANs)
4. Rock Pi 4 SE IDS (passive detection)
5. Centralized visibility (ELK)

## Network Design Essentials

### VLAN Segmentation
- **VLAN 10** (192.168.10.0/24): Trusted devices
- **VLAN 20** (192.168.20.0/24): Infrastructure (server, DNS, ELK) - management network
- **VLAN 30** (192.168.30.0/24): IoT/Guest (isolated)
- **VLAN 40** (192.168.40.0/24): Lab VMs
- **VLAN 99** (192.168.99.0/24): Honeypot DMZ (completely isolated except ELK logging)

### Key IP Addresses
- Server: 192.168.20.10
- Switch: 192.168.20.11
- Rock Pi 4 SE (IDS): 192.168.20.20
- DNS: 192.168.20.53
- Rock Pi E (IPS): Transparent bridge (no IP)

### Access Methods
- VPN: WireGuard on port 51820 (only exposed internet port)
- Kibana: https://192.168.20.10:443 (via VPN only)
- All management via VLAN 20 through VPN

## Configuration File Formats

**OpenWrt configs** (UCI format, no file extension):
- `network/openwrt/network-config` - VLAN interfaces, WireGuard
- `network/openwrt/dhcp-config` - DHCP per VLAN, static assignments
- `network/openwrt/firewall-config` - Zones, rules, port forwarding

**Suricata configs** (YAML):
- `ids-ips/rockpi-e-ips/suricata.yaml` - IPS mode, 1GB RAM optimization, inline bridge
- `ids-ips/rockpi4-ids/suricata.yaml` - IDS mode, 4GB RAM, passive SPAN monitoring

**ELK Stack** (Docker Compose):
- `server/elk-stack/docker-compose.yml` - Podman/Docker compose for Elasticsearch + Kibana

**WireGuard** (INI format):
- `vpn/wireguard/client-template.conf` - Client configuration template
- `vpn/wireguard/generate-client.sh` - Automated client generation with QR codes

## Common Operations

### Deploy ELK Stack (Primary Deployment Script)
```bash
# On CentOS server (192.168.20.10)
sudo bash scripts/deployment/deploy-elk-stack.sh

# This script:
# - Configures system (vm.max_map_count, swappiness)
# - Creates directory structure
# - Generates configs (Elasticsearch, Kibana)
# - Deploys containers via Podman
# - Configures firewall
# - Creates systemd service
```

### Generate WireGuard Client
```bash
cd vpn/wireguard
bash generate-client.sh <client-name> <ip-octet>
# Example: bash generate-client.sh laptop 2
# Creates: laptop-wg0.conf + QR code
# Outputs: OpenWrt config to add to router
```

### Verify Suricata IPS/IDS
```bash
# On Rock Pi E (IPS)
sudo systemctl status suricata
brctl show  # Verify bridge
sudo tail -f /var/log/suricata/fast.log

# On Rock Pi 4 SE (IDS)
sudo systemctl status suricata
sudo tcpdump -i eth0 -c 100  # Verify SPAN traffic
sudo tail -f /var/log/suricata/eve.json | jq .
```

### Check ELK Stack
```bash
# Verify services
podman ps
curl http://192.168.20.10:9200  # Elasticsearch
curl http://192.168.20.10:443/api/status  # Kibana

# Check logs
podman logs elasticsearch
podman logs kibana
```

### Apply OpenWrt Configs
```bash
# SSH to router
ssh root@192.168.20.1

# Apply network changes
cp network-config /etc/config/network
/etc/init.d/network restart

# Apply firewall changes
cp firewall-config /etc/config/firewall
/etc/init.d/firewall restart

# Verify
wg show  # WireGuard status
iptables -L -v -n  # Firewall rules
```

## Critical Configuration Relationships

### Rock Pi E IPS Bridge Setup
The IPS runs as a **transparent bridge** between router and switch:
```
eth0 (WAN side) ←→ br0 ←→ eth1 (LAN side)
```
- Suricata runs in `copy-mode: ips` with AF_PACKET
- Must disable hardware offloading: `ethtool -K eth0 gro off lro off tso off gso off`
- Bridge has no IP address (invisible layer 2)
- Low RAM (1GB) requires conservative tuning in suricata.yaml

### HP Switch SPAN Port
Port 22 mirrors all traffic to Rock Pi 4 SE:
```
show mirror  # On switch console
Source: ports 1-21, 23-24
Destination: port 22
Direction: both
```
Rock Pi 4 SE connects to port 22 and runs Suricata in passive mode (no blocking).

### T-Pot Honeypot Isolation
T-Pot VM (VLAN 99) is **strictly isolated**:
- Can reach: Internet (all ports), Elasticsearch (192.168.20.10:9200), DNS (192.168.20.53:53)
- Cannot reach: Any other internal VLANs
- Enforced by OpenWrt firewall rules in `network/openwrt/firewall-config`
- Port forwarding from internet to specific honeypot services (SSH:2222, HTTP:8080, etc.)

### ELK Data Retention
Configured via Index Lifecycle Management (ILM):
- Hot phase: 0-7 days (full indexing)
- Warm phase: 7-30 days (read-only, compressed)
- Delete: After 30 days
- Adjust in Kibana or via API based on disk space

## Deployment Order (Dependencies)

This order must be followed for successful installation:

1. **Network** (Switch + Router) - Establishes VLANs and routing
2. **VPN** (WireGuard) - Remote access to infrastructure
3. **Server Base** (CentOS) - OS and RAID setup
4. **ELK Stack** - Logging infrastructure (use deploy-elk-stack.sh)
5. **Rock Pi 4 SE IDS** - Passive monitoring (requires SPAN port from switch)
6. **Rock Pi E IPS** - Inline protection (requires functioning network)
7. **Collectors** (Filebeat/Metricbeat) - Data shipping to ELK
8. **Additional services** (DNS, NAS, Backup, T-Pot)

## Security Considerations When Modifying

**Never commit:**
- WireGuard private keys
- Elasticsearch passwords (if enabled)
- MAC addresses (replace with placeholders)
- Public IP addresses
- `.env` files

**Always verify:**
- T-Pot isolation (test from honeypot: `ping 192.168.10.100` should fail)
- VPN restricts to VLAN 20 only (test from VPN client: `ping 192.168.10.100` should fail)
- Firewall rules block inter-VLAN traffic as designed
- Rock Pi E IPS is actually dropping malicious traffic (test with EICAR)

**MAC address handling:**
All DHCP static assignments use placeholder MACs (XX:XX:XX:XX:XX:XX, YY:YY:YY:YY:YY:YY, etc.). Replace with actual MAC addresses during deployment.

## Performance Constraints

### Rock Pi E (IPS) - 1GB RAM
- Conservative Suricata tuning required
- Flow memcap: 256MB
- Stream memcap: 256MB
- 1-2 worker threads maximum
- Disable unused protocols if CPU >80%

### Rock Pi 4 SE (IDS) - 4GB RAM
- More aggressive detection possible
- Flow memcap: 512MB
- Stream memcap: 1GB
- 2-4 worker threads
- Can enable all protocols and deep inspection

### CentOS Server - 64GB RAM
- Elasticsearch heap: 16-24GB (50% of available RAM)
- Kibana: 2-4GB
- Remaining for VMs and OS

### Network Throughput
- Target: 120 Mbit/s internet connection
- IPS overhead: <5ms latency
- Expected packet drops: <0.1%

## Troubleshooting Approach

**Start with:** `docs/troubleshooting.md` - comprehensive guide with diagnostic commands

**Component-specific:**
- Each component directory has README.md with troubleshooting section
- Check service status first: `systemctl status <service>` or `podman ps`
- Check logs: documented in troubleshooting.md

**Network issues:**
1. Verify physical connectivity
2. Check VLAN configuration on switch
3. Verify firewall rules (OpenWrt)
4. Test with `ping` and `tcpdump`

**No data in Kibana:**
1. Check Elasticsearch is running: `curl http://192.168.20.10:9200`
2. Verify Filebeat on Rock Pi 4 SE: `systemctl status filebeat`
3. Test Filebeat output: `filebeat test output`
4. Check index patterns match actual indices

## File Modification Guidelines

### When modifying OpenWrt configs:
- Use UCI format (config blocks with options)
- Test with `uci show` before applying
- Backup existing config first
- Restart service after changes: `/etc/init.d/<service> restart`

### When modifying Suricata configs:
- Validate YAML syntax: `suricata -T -c /etc/suricata/suricata.yaml`
- Test rule loading: `suricatasc -c "reload-rules"`
- Monitor performance after changes: `htop` and packet drop stats
- Reload without full restart when possible

### When modifying ELK configs:
- Elasticsearch changes require container restart
- Update docker-compose.yml for persistent changes
- Verify Elasticsearch cluster health after: `curl http://localhost:9200/_cluster/health`
- Kibana auto-detects most Elasticsearch config changes

## Documentation Structure

**High-level docs** (docs/):
- `architecture.md` - System design, components, data flows
- `network-design.md` - IP plans, VLANs, firewall matrix
- `installation-guide.md` - Complete step-by-step (8-12 hours)
- `quick-start.md` - Minimal 30-min setup
- `troubleshooting.md` - Diagnostic procedures

**Component docs** (README.md in each directory):
- Installation steps
- Configuration details
- Maintenance procedures
- Component-specific troubleshooting

## Adding New Components

When extending this project:

1. Create component directory under appropriate parent (network/, server/, etc.)
2. Add README.md with:
   - Component overview
   - Installation steps
   - Configuration reference
   - Troubleshooting section
3. Add configuration files with extensive comments
4. Update `docs/architecture.md` with component description
5. Update `docs/network-design.md` if network changes required
6. Update `PROJECT_STRUCTURE.md`
7. Create deployment script if complex setup (follow `deploy-elk-stack.sh` pattern)

## References to External Systems

**Suricata:** Uses Emerging Threats ruleset (updated via `suricata-update`)
**Elasticsearch/Kibana:** Version 8.11.0 (pinned in docker-compose.yml)
**OpenWrt:** UCI configuration system
**WireGuard:** Modern VPN protocol (UDP port 51820)
**T-Pot:** Multi-honeypot platform (external VM, see T-Pot documentation)
