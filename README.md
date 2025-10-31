# HomeSec - Home Security & Monitoring Project

Ett komplett hem-IDS/IPS system med centraliserad loggning, visualisering och monitoring.

## Översikt

HomeSec är ett projekt för att bygga ett professionellt säkerhetssystem hemma med:
- Intrusion Detection & Prevention (IDS/IPS)
- Honeypot monitoring
- Centraliserad loggning och visualisering
- Nätverksmonitoring
- System health monitoring
- Säker VPN-åtkomst

## Hårdvara

### Nätverk
- **Router**: OpenWrt (UPS-backup)
- **Switch**: HP 2530-24G-PoEP (J9773A) med UPS
- **WiFi**: 6x Access Points (3st med UPS, 3st utan)

### Säkerhetsenheter
- **Rock Pi E** (1GB RAM, 2x ETH, UPS): Suricata IPS - Inline bridge mode
- **Rock Pi 4 SE** (4GB RAM, UPS): Suricata IDS - Passiv monitoring via SPAN

### Server (CentOS)
- **CPU**: 12 kärnor
- **RAM**: 64GB
- **Storage**: 2x 4TB HDD i RAID
- **GPU**: 8GB VRAM (framtida AI/ML projekt)

**Tjänster på server:**
- Elasticsearch + Kibana (Podman containers)
- BIND DNS
- NAS (Samba/NFS)
- Backup system
- QEMU/KVM VMs:
  - Alma Linux (T-Pot honeypots)
  - Windows Server 2019 (Lab)
  - Windows 11 (Lab)

## Nätverksarkitektur

```
Internet (120 Mbit/s)
    ↓
[OpenWrt Router] ← VPN endpoint, Firewall
    ↓
[Rock Pi E - IPS] ← Suricata inline bridge
    ↓
[HP 2530 Switch] ← VLAN segmentering, SPAN port
    ├─ [Rock Pi 4 SE - IDS] ← Passiv monitoring
    ├─ [6x WiFi APs] ← WiFi coverage
    └─ [CentOS Server] ← ELK, DNS, NAS, VMs
```

## VLAN Segmentering

| VLAN | Namn | Syfte |
|------|------|-------|
| 10 | Trusted LAN | Trusted devices (datorer, telefoner) |
| 20 | Infrastructure | Server, NAS, DNS, ELK |
| 30 | IoT/Guest | Opålitliga enheter, gäster |
| 40 | Lab | Virtuella maskiner (Windows, test) |
| 99 | Honeypot DMZ | T-Pot (ISOLERAD) |

## Data Källor till Kibana

### Säkerhet
- Suricata IPS (Rock Pi E) - Blockerade attacker
- Suricata IDS (Rock Pi 4 SE) - Full trafik analys
- T-Pot Honeypots - Attack patterns, malware
- OpenWrt Firewall logs
- BIND DNS logs

### System Health
- Server metrics (CPU, RAM, disk, GPU)
- RAID status och disk health
- VM resource usage
- UPS status (batterinivå, runtime, power events)

### Nätverk
- Switch metrics (port stats, PoE usage)
- WiFi metrics (clients per AP, signal strength)
- Network flows (bandwidth per VLAN)
- Top talkers

### Backup
- Backup status (success/failure)
- Backup size och duration
- Disk usage trend
- Retention compliance

## Dokumentation

- [Architecture](docs/architecture.md) - Detaljerad systemarkitektur
- [Network Design](docs/network-design.md) - VLAN, IP-plan, routing
- [Installation Guide](docs/installation-guide.md) - Steg-för-steg installation
- [Troubleshooting](docs/troubleshooting.md) - Felsökning

## Snabbstart

### Quick Start (30 minuter)
För att snabbt få upp ett grundläggande system, se [Quick Start Guide](docs/quick-start.md).

### Fullständig Installation (8-12 timmar)
För komplett setup, se [Installation Guide](docs/installation-guide.md).

### Installationsordning
1. Nätverkskonfiguration (VLAN, switch, router)
2. WireGuard VPN setup
3. ELK Stack på CentOS server (använd `scripts/deployment/deploy-elk-stack.sh`)
4. Suricata IDS på Rock Pi 4 SE (passiv via SPAN)
5. Suricata IPS på Rock Pi E (inline bridge)
6. Data collectors (Filebeat, Metricbeat)
7. BIND DNS server
8. NAS (Samba/NFS)
9. Backup system
10. T-Pot honeypot (isolerad)
11. Dashboards i Kibana

## Säkerhet

- Alla känsliga credentials lagras i separata `.env` filer (ej committade)
- T-Pot honeypot är isolerad i egen VLAN med strikta firewall-regler
- VPN är enda sättet att komma åt management interfaces
- Minimal exponering mot internet

## Backup

Automatisk backup körs dagligen:
- VM snapshots/backups
- Podman container volumes
- Konfigurationsfiler
- Elasticsearch snapshots (optional)

Backups lagras på RAID array (2x 4TB).

## Licens

Detta är ett personligt projekt för hemmabruk.

## Författare

Julian Rieger
