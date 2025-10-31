# HomeSec - Systemarkitektur

## Översikt

HomeSec är ett fler-lagers säkerhetssystem designat för hemmabruk med enterprise-liknande funktionalitet.

## Komponenter

### 1. Perimeter Security

#### OpenWrt Router
**Funktion**: Första försvarslinjen mot internet
- Stateful firewall
- NAT
- WireGuard VPN endpoint
- Port forwarding till T-Pot honeypot (med restriktioner)
- DNS forwarding till BIND server
- NetFlow/sFlow export

**UPS**: Ja

#### Rock Pi E - IPS (Inline Bridge)
**Specifikationer**: 1GB RAM, 2x Ethernet portar

**Funktion**: Aktiv hotblockering
- Suricata i IPS-läge
- Transparent bridge mellan router och switch (eth0 ↔ eth1)
- Blockerar aktivt skadlig trafik i realtid
- Minimal latens (< 5ms vid 120 Mbit/s)

**Configuration**:
- Mode: Bridge + IPS
- Rules: Emerging Threats, ETPRO
- Actions: Drop, Reject, Alert
- Log destination: Rock Pi 4 SE + ELK Stack

**UPS**: Ja

### 2. Network Core

#### HP 2530-24G-PoEP Switch (J9773A)
**Funktion**: VLAN segmentering och port mirroring

**Features**:
- VLAN tagging (802.1Q)
- Port mirroring (SPAN) - All traffic → Rock Pi 4 SE
- SNMP monitoring
- sFlow export
- PoE+ (till access points)
- Link aggregation (om behövs framtida)

**VLAN Konfiguration**:
- VLAN 10: Trusted LAN (datorer, telefoner)
- VLAN 20: Infrastructure (Server, NAS, DNS, ELK)
- VLAN 30: IoT/Guest WiFi
- VLAN 40: Lab VMs (Windows 2019, Windows 11)
- VLAN 99: Honeypot DMZ (T-Pot - ISOLERAD)

**UPS**: Ja

#### 6x WiFi Access Points
**Funktion**: WiFi coverage

**Konfiguration**:
- SSID 1: "HomeSec-Trusted" → VLAN 10 (WPA3/WPA2)
- SSID 2: "HomeSec-IoT" → VLAN 30 (WPA2)
- SSID 3: "HomeSec-Guest" → VLAN 30 (WPA2, isolerad)

**Power**:
- 3x APs: UPS (kritiska områden)
- 3x APs: Ingen UPS

**Monitoring**:
- SNMP stats
- Client count
- Signal strength
- Channel utilization

### 3. Security Monitoring

#### Rock Pi 4 SE - IDS (Passive)
**Specifikationer**: 4GB RAM, Ethernet

**Funktion**: Djup paketinspektion utan throughput påverkan
- Suricata i IDS-läge
- Mottar ALL trafik via SPAN port från switch
- Ingen påverkan på nätverksprestanda
- Kör även data collectors (Filebeat, Metricbeat)

**Configuration**:
- Mode: AF_PACKET / PCAP
- Rules: Emerging Threats, custom rules
- Log destination: ELK Stack
- Collectors: Filebeat, Metricbeat, Packetbeat

**UPS**: Ja

### 4. Central Server (CentOS)

**Specifikationer**:
- CPU: 12 kärnor
- RAM: 64GB
- Storage: 2x 4TB HDD (RAID 1 eller RAID 10)
- GPU: 8GB VRAM
- Network: VLAN 20 (Infrastructure)

**Tjänster (Direkt på CentOS)**:
1. **Elasticsearch** (Podman container)
   - Loggsökning och indexering
   - 7 dagars hot data, 30 dagars warm data
   - Snapshots till RAID

2. **Kibana** (Podman container)
   - Visualisering
   - Dashboards
   - Alerting

3. **Logstash** (Podman container, optional)
   - Log parsing och enrichment
   - GeoIP lookup
   - Threat intelligence enrichment

4. **BIND DNS**
   - Intern DNS server
   - Query logging → Elasticsearch
   - DNS-based blacklisting

5. **NAS (Samba/NFS)**
   - File shares till nätverket
   - Backup storage
   - VM storage

6. **Backup System**
   - Dagliga VM backups
   - Container volume backups
   - Config backups
   - Borg Backup med deduplikation

7. **Monitoring Agents**
   - Filebeat (log shipping)
   - Metricbeat (system metrics)
   - RAID monitoring (mdadm)
   - UPS monitoring (om ansluten)

**Virtuella Maskiner (QEMU/KVM)**:

1. **Alma Linux - T-Pot** (VLAN 99)
   - Honeypot suite
   - ISOLERAD från övriga nätverket
   - Endast utgående trafik för log shipping
   - Incoming från internet (begränsade portar)

2. **Windows Server 2019** (VLAN 40)
   - Lab/test environment
   - Winlogbeat för logging

3. **Windows 11** (VLAN 40)
   - Lab/test environment
   - Winlogbeat för logging

**UPS**: Nej (men rekommenderas för framtiden)

### 5. VPN Access

#### WireGuard på OpenWrt Router
**Funktion**: Säker fjärråtkomst till management interfaces

**Konfiguration**:
- UDP port 51820 (endast exponerad port mot internet)
- Endast tillgång till VLAN 20 (Infrastructure)
- No split-tunneling (all traffic via VPN för säkerhet)
- Maximum 5 concurrent clients

**Användning**:
- Remote access till Kibana
- SSH till server
- Management av switch/router
- INGEN direkt access till VLAN 99 (T-Pot)

## Data Flow

### Normal Traffic Flow
```
Internet → OpenWrt Router → Rock Pi E (IPS) → HP Switch → Devices
                                                    ↓
                                            Rock Pi 4 SE (IDS, SPAN)
                                                    ↓
                                            Elasticsearch (Server)
```

### Log Flow
```
All devices → Filebeat → Logstash (optional) → Elasticsearch → Kibana
```

### Honeypot Flow
```
Internet → OpenWrt Router → HP Switch (VLAN 99) → T-Pot VM
                                                       ↓
                                                   Filebeat
                                                       ↓
                                                 Elasticsearch
```

### VPN Access Flow
```
Remote Client → WireGuard (UDP 51820) → OpenWrt Router → VLAN 20 only
```

## Security Layers

### Layer 1: Perimeter
- OpenWrt firewall
- Port restrictions
- Rate limiting

### Layer 2: IPS
- Rock Pi E blocks malicious traffic inline
- Signature-based detection
- Protocol anomaly detection

### Layer 3: Network Segmentation
- VLAN isolation
- Inter-VLAN firewall rules
- T-Pot completely isolated

### Layer 4: Detection
- Rock Pi 4 SE passive monitoring
- Full packet capture (if needed)
- Behavioral analysis

### Layer 5: Visibility
- Centralized logging in Elasticsearch
- Real-time dashboards
- Alerting on anomalies

### Layer 6: Backup & Recovery
- Daily backups
- RAID redundancy
- Config versioning

## Monitoring & Alerting

### Metrics Collected
1. **Security Events**
   - IPS/IDS alerts
   - Firewall blocks
   - Honeypot attacks
   - DNS queries (anomalies)

2. **System Health**
   - CPU, RAM, Disk usage
   - RAID status
   - Disk SMART data
   - Container health
   - VM resource usage

3. **Network Performance**
   - Bandwidth per VLAN
   - Top talkers
   - Protocol distribution
   - WiFi client stats
   - Switch port stats

4. **Power & Environment**
   - UPS battery level
   - UPS runtime
   - Power events (outages)
   - Device uptime

5. **Backup Status**
   - Last successful backup
   - Backup duration
   - Backup size
   - Failures/errors

### Alerts (Kibana Alerting)
- 🔴 **Critical**: IPS blocking spikes, RAID degraded, backup failed
- 🟡 **Warning**: High resource usage, UPS on battery, no backup 24h
- 🔵 **Info**: Successful backup, system updates available

## Scalability

### Short-term
- Funktionell med nuvarande hårdvara för 120 Mbit/s

### Medium-term (om internet uppgraderas)
- Rock Pi E kan hantera upp till 500 Mbit/s med IPS aktivt
- Rock Pi 4 SE kan hantera > 1 Gbit/s i passiv IDS mode
- ELK Stack kan skalas genom att lägga till fler Elasticsearch noder

### Long-term (future-proof)
- GPU kan användas för ML-baserad threat detection
- Elasticsearch cluster (multi-node)
- Dedikerad log storage (kalla data till billigare diskar)
- Video surveillance integration (GPU för analysering)

## Underhåll

### Dagligen
- Automatisk backup
- Log rotation
- Threat intelligence feed updates

### Veckovis
- Kibana dashboard review
- Alert fine-tuning
- Backup verification (test restore)

### Månadsvis
- Suricata rule updates
- System updates (CentOS, OpenWrt, Rock Pis)
- RAID scrub
- Disk health check (SMART)

### Kvartalsvis
- Security audit
- Performance review
- Capacity planning
- VPN client key rotation

## Disaster Recovery

### Scenarios
1. **Server failure**: Restore från backup, VMs på annan hårdvara
2. **RAID disk failure**: RAID rebuild, replace disk
3. **Switch failure**: Temporärt direkt-ansluten till router
4. **IPS failure**: Bypass (direkt router→switch), felanmälan
5. **Power outage**: UPS runtime ~30 min för kritiska enheter

### Recovery Time Objectives (RTO)
- Critical services (DNS, Firewall): < 15 minuter
- Monitoring (ELK): < 1 timme
- Full restore: < 4 timmar

### Recovery Point Objectives (RPO)
- Configs: 0 (versioned i git)
- VMs: 24 timmar (daglig backup)
- Logs: 0 (real-time streaming)

## Compliance & Best Practices

- Passwords lagras i separate `.env` filer (ej committade till git)
- SSH keys för all remote access
- Minimal privilege principle
- Regular patching
- Audit logs för all admin access
- Encrypted backups

## Kostnadseffektivitet

**One-time costs**:
- Hårdvara: Already owned
- Setup tid: ~40 timmar

**Recurring costs**:
- Elektricitet: ~50-100W kontinuerlig (server + networking)
- UPS-batterier: Var 3-5 år
- Diskar: Var 5 år

**Alternativ kostnad (cloud equivalent)**:
- IDS/IPS: $100-500/månad
- SIEM: $200-1000/månad
- Total saving: ~$3600-18000/år

## Framtida Förbättringar

1. **AI/ML Threat Detection** (använd GPU)
2. **Network Behavior Analysis** (baselines, anomalies)
3. **Automated Response** (auto-block IPs, isolate devices)
4. **Video Surveillance** (GPU för analysering)
5. **Mobile App** (push notifications, dashboard)
6. **Hardware sensors** (temperatur, fuktighet, rök)
7. **Distributed honeypots** (externa VPS som kanariefåglar)
