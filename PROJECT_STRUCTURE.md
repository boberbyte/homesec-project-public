# HomeSec Project Structure

## Overview

This document provides a complete overview of the HomeSec project structure and file organization.

## Directory Tree

```
homesec-project/
├── README.md                          # Main project documentation
├── PROJECT_STRUCTURE.md               # This file
│
├── docs/                              # Documentation
│   ├── architecture.md                # Detailed system architecture
│   ├── network-design.md              # VLAN design, IP plans, routing
│   ├── installation-guide.md          # Complete step-by-step installation
│   ├── quick-start.md                 # 30-minute quick setup guide
│   └── troubleshooting.md             # Comprehensive troubleshooting
│
├── network/                           # Network configuration
│   ├── hp-switch/                     # HP 2530-24G Switch
│   │   ├── README.md                  # Switch setup and configuration
│   │   └── hp2530-config.txt          # Switch configuration commands
│   │
│   └── openwrt/                       # OpenWrt Router
│       ├── README.md                  # Router setup and maintenance
│       ├── network-config             # Network/VLAN configuration
│       ├── dhcp-config                # DHCP configuration per VLAN
│       └── firewall-config            # Firewall zones and rules
│
├── vpn/                               # VPN configuration
│   ├── wireguard/                     # WireGuard VPN
│   │   ├── README.md                  # WireGuard setup and client config
│   │   ├── client-template.conf      # Client configuration template
│   │   └── generate-client.sh        # Script to generate client configs
│   │
│   └── headscale/                     # Alternative: Headscale (empty)
│       └── (for future use)
│
├── ids-ips/                           # Intrusion Detection/Prevention
│   ├── rockpi-e-ips/                  # Rock Pi E - IPS (Inline)
│   │   ├── README.md                  # IPS setup and maintenance
│   │   └── suricata.yaml              # Suricata IPS configuration
│   │
│   └── rockpi4-ids/                   # Rock Pi 4 SE - IDS (Passive)
│       ├── README.md                  # IDS setup and maintenance
│       └── suricata.yaml              # Suricata IDS configuration
│
├── server/                            # CentOS Server components
│   ├── elk-stack/                     # ELK Stack (Elasticsearch + Kibana)
│   │   ├── README.md                  # ELK setup, usage, maintenance
│   │   └── docker-compose.yml         # Podman/Docker compose for ELK
│   │
│   ├── dns/                           # BIND DNS Server
│   │   └── (to be populated)
│   │
│   ├── nas/                           # NAS (Samba/NFS)
│   │   └── (to be populated)
│   │
│   ├── backup/                        # Backup system
│   │   └── (to be populated)
│   │
│   └── monitoring/                    # Monitoring agents
│       └── (Filebeat, Metricbeat configs)
│
├── dashboards/                        # Kibana dashboards
│   ├── kibana/                        # Kibana dashboard exports
│   │   └── (dashboard JSON files)
│   │
│   └── templates/                     # Dashboard templates
│       └── (template files)
│
├── scripts/                           # Automation scripts
│   ├── deployment/                    # Deployment scripts
│   │   └── deploy-elk-stack.sh       # ELK Stack deployment script
│   │
│   └── maintenance/                   # Maintenance scripts
│       └── (backup, update scripts)
│
└── firewall/                          # Firewall configurations
    ├── openwrt-rules/                 # OpenWrt firewall rules
    │   └── (detailed rule configs)
    │
    └── tpot-isolation/                # T-Pot isolation rules
        └── (T-Pot firewall config)
```

## File Descriptions

### Root Level

- **README.md**: Main project documentation with overview, hardware specs, architecture diagram, and quick links
- **PROJECT_STRUCTURE.md**: This file - complete project structure reference

### Documentation (docs/)

- **architecture.md**:
  - Detailed component descriptions
  - Data flow diagrams
  - Security layers
  - Scalability considerations
  - Maintenance schedules
  - Disaster recovery plans

- **network-design.md**:
  - IP addressing plan (all VLANs)
  - VLAN segmentation strategy
  - Firewall rules matrix
  - DNS configuration
  - WiFi SSID mapping
  - Port mirroring setup
  - QoS policies

- **installation-guide.md**:
  - Complete step-by-step installation
  - Installation order and dependencies
  - Verification steps
  - Security checklist
  - Estimated time per phase

- **quick-start.md**:
  - 30-minute minimal setup
  - Basic monitoring without full features
  - Quick verification steps
  - Next steps guidance

- **troubleshooting.md**:
  - Common issues and solutions
  - Diagnostic commands
  - Service-specific troubleshooting
  - Performance tuning
  - Log collection

### Network Configuration (network/)

#### HP Switch (network/hp-switch/)

- **README.md**:
  - Installation steps
  - Port assignments
  - VLAN verification
  - SPAN port configuration
  - PoE management
  - Backup procedures

- **hp2530-config.txt**:
  - Complete switch configuration
  - VLAN definitions
  - Port mirroring setup
  - SNMP and sFlow configuration

#### OpenWrt Router (network/openwrt/)

- **README.md**:
  - Router setup and configuration
  - Firewall management
  - VPN integration
  - Troubleshooting

- **network-config**:
  - VLAN interface configuration
  - Bridge setup
  - WireGuard interface

- **dhcp-config**:
  - DHCP servers per VLAN
  - Static IP assignments
  - DNS server assignments

- **firewall-config**:
  - Zone definitions
  - Forwarding rules
  - Port forwarding (honeypot)
  - Rate limiting

### VPN (vpn/)

#### WireGuard (vpn/wireguard/)

- **README.md**:
  - Server setup
  - Client configuration
  - Key management
  - Testing procedures
  - Security best practices

- **client-template.conf**:
  - Template for client configurations
  - Commented with instructions

- **generate-client.sh**:
  - Automated client generation
  - Creates keys and configs
  - Generates QR codes for mobile

### IDS/IPS (ids-ips/)

#### Rock Pi E IPS (ids-ips/rockpi-e-ips/)

- **README.md**:
  - Bridge configuration
  - Suricata IPS setup
  - Performance tuning
  - Rule management

- **suricata.yaml**:
  - Inline IPS configuration
  - Optimized for 1GB RAM
  - AF_PACKET bridge mode
  - Rule actions (drop, reject, alert)

#### Rock Pi 4 SE IDS (ids-ips/rockpi4-ids/)

- **README.md**:
  - Passive monitoring setup
  - SPAN port verification
  - Filebeat integration

- **suricata.yaml**:
  - Passive IDS configuration
  - Optimized for 4GB RAM
  - More aggressive detection
  - Extended protocol support

### Server (server/)

#### ELK Stack (server/elk-stack/)

- **README.md**:
  - Installation and configuration
  - Data retention policies
  - Backup procedures
  - Performance tuning
  - Security hardening

- **docker-compose.yml**:
  - Elasticsearch container
  - Kibana container
  - Logstash container (optional)
  - Network and volume configuration

### Scripts (scripts/)

#### Deployment (scripts/deployment/)

- **deploy-elk-stack.sh**:
  - Automated ELK Stack deployment
  - System tuning
  - Firewall configuration
  - Service verification
  - Creates systemd service

## Configuration Files Format

### YAML Files
- Suricata configurations
- Elasticsearch/Kibana configs
- Docker Compose

### UCI Format
- OpenWrt network configuration
- OpenWrt DHCP configuration
- OpenWrt firewall rules

### INI Format
- WireGuard client configurations

### Shell Scripts
- Deployment automation
- Client generation
- Maintenance tasks

## How to Navigate This Project

### For Installation

1. Start with **docs/installation-guide.md** for complete setup
2. OR **docs/quick-start.md** for minimal 30-min setup
3. Follow component-specific READMEs in each directory
4. Use **docs/troubleshooting.md** when issues arise

### For Configuration

1. Reference **docs/network-design.md** for IP plans and VLANs
2. Component configs in respective directories:
   - Switch: `network/hp-switch/`
   - Router: `network/openwrt/`
   - VPN: `vpn/wireguard/`
   - IDS/IPS: `ids-ips/`
   - ELK: `server/elk-stack/`

### For Maintenance

1. Each component has a README with maintenance procedures
2. **docs/architecture.md** has maintenance schedules
3. **scripts/maintenance/** contains automation scripts

### For Troubleshooting

1. **docs/troubleshooting.md** is the primary resource
2. Component-specific troubleshooting in each README
3. Check logs as documented in troubleshooting guide

## File Naming Conventions

- **README.md**: Primary documentation for each directory
- **\*.yaml**: YAML configuration files (Suricata, ELK)
- **\*.conf**: Configuration files (WireGuard, etc.)
- **\*.yml**: Docker Compose files
- **\*-config**: OpenWrt UCI configuration files (no extension)
- **\*.sh**: Shell scripts (executable)
- **\*.md**: Markdown documentation

## Configuration Management

### Version Control

- All configurations should be version controlled (git)
- Sensitive data (passwords, keys) should be in `.env` files (not committed)
- Use `.gitignore` to exclude sensitive files

### Backup Strategy

- Configuration files: Daily backup to RAID
- Elasticsearch snapshots: Daily to RAID
- VM images: Weekly backup
- All configs in git repository

## Component Dependencies

### Installation Order
```
1. Network (Switch + Router) ────┐
                                  ├──> 2. VPN
                                  │
3. Server Base ──> 4. ELK Stack ─┼──> 5. IDS (Rock Pi 4 SE)
                                  │
                                  └──> 6. IPS (Rock Pi E)
                                  │
                                  ├──> 7. DNS
                                  ├──> 8. NAS
                                  ├──> 9. Backup
                                  └──> 10. T-Pot
```

### Runtime Dependencies
```
Internet
  └─> OpenWrt Router
        └─> Rock Pi E (IPS) [bridge]
              └─> HP Switch
                    ├─> Rock Pi 4 SE (IDS) [SPAN]
                    │     ├─> Suricata
                    │     ├─> Filebeat ──────┐
                    │     └─> Metricbeat ────┤
                    │                         │
                    └─> CentOS Server         │
                          ├─> Elasticsearch <─┘
                          ├─> Kibana
                          ├─> BIND DNS
                          ├─> NAS
                          └─> T-Pot VM (VLAN 99)
```

## Future Additions

The following directories are placeholders for future components:

- `server/dns/` - BIND DNS configuration
- `server/nas/` - Samba/NFS configuration
- `server/backup/` - Backup scripts and configs
- `server/monitoring/` - Filebeat/Metricbeat configs
- `dashboards/kibana/` - Dashboard exports
- `firewall/openwrt-rules/` - Detailed firewall rules
- `firewall/tpot-isolation/` - T-Pot isolation config
- `scripts/maintenance/` - Maintenance automation

## Getting Started Paths

### Path 1: Complete Installation (Recommended)
```
1. Read README.md
2. Review docs/architecture.md
3. Follow docs/installation-guide.md
4. Use component READMEs for each step
5. Deploy using scripts/deployment/
```

### Path 2: Quick Start (Testing)
```
1. Read README.md
2. Follow docs/quick-start.md
3. Verify basic functionality
4. Expand using installation-guide.md
```

### Path 3: Specific Component Only
```
1. Read docs/architecture.md for context
2. Navigate to component directory
3. Follow component README.md
4. Configure and test
```

## Documentation Philosophy

- **README.md**: "How to" guides with practical steps
- **\*.md in docs/**: Conceptual documentation and reference
- **Configuration files**: Heavily commented with explanations
- **Scripts**: Include usage examples and error handling

## Support and Updates

- Primary documentation: This project
- Community support: See component-specific forums
- Updates: Check component official documentation
- Custom modifications: Document in local notes

## Contributing

If expanding this project:
1. Follow existing directory structure
2. Create README.md for new components
3. Document configuration thoroughly
4. Update this PROJECT_STRUCTURE.md
5. Add to main README.md

## License

This project is for personal/educational use. See main README.md.
