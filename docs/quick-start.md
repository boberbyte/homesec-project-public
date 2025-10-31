# HomeSec - Quick Start Guide

## Prerequisites

- All hardware connected and powered on
- CentOS Server installed and accessible
- Basic familiarity with Linux command line
- Console or SSH access to all devices

## 30-Minute Quick Setup (Minimum Viable System)

This guide gets a basic monitoring system running quickly. Full installation takes 8-12 hours.

### Step 1: Network (5 minutes)

**HP Switch**: Basic config
```bash
# Connect via console
# Set management IP
vlan 20
ip address 192.168.20.11 255.255.255.0
exit
ip default-gateway 192.168.20.1
write memory
```

**OpenWrt Router**: Use web UI
1. Set LAN IP: 192.168.20.1
2. Configure WAN (DHCP or PPPoE)
3. Save & Apply

### Step 2: Server Preparation (5 minutes)

```bash
# On CentOS Server
sudo dnf update -y
sudo dnf install -y podman podman-compose git

# Set static IP (if not already)
sudo nmtui  # Use NetworkManager TUI

# Configure system
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### Step 3: Deploy ELK Stack (10 minutes)

```bash
# Clone or copy project files
git clone <your-repo> /opt/homesec
# OR
# Copy files manually to /opt/homesec/

# Run deployment script
cd /opt/homesec/scripts/deployment
sudo bash deploy-elk-stack.sh

# Wait for services to start (~2 minutes)
```

### Step 4: Configure Rock Pi 4 SE - IDS (5 minutes)

```bash
# On Rock Pi 4 SE
sudo apt update && sudo apt install -y suricata filebeat

# Set static IP: 192.168.20.20
sudo nmtui

# Quick Suricata config
sudo cp /opt/homesec/ids-ips/rockpi4-ids/suricata.yaml /etc/suricata/
sudo suricata-update
sudo systemctl enable --now suricata

# Quick Filebeat config
sudo cp /opt/homesec/server/monitoring/filebeat-rockpi4.yml /etc/filebeat/filebeat.yml
sudo systemctl enable --now filebeat
```

### Step 5: Verify (5 minutes)

```bash
# Check Elasticsearch
curl http://192.168.20.10:9200

# Check Kibana (wait 2-3 minutes for initialization)
curl http://192.168.20.10:443/api/status

# Access Kibana UI
# Open browser: https://192.168.20.10:443

# Create index pattern: homesec-*

# Check for data
# Navigate to Discover in Kibana
```

## What You Have Now

✅ **Central logging**: All logs go to Elasticsearch
✅ **Visualization**: Kibana dashboards available
✅ **IDS monitoring**: Suricata passively monitoring network (via SPAN)
✅ **Basic security**: Network segmentation with VLANs

## What's Missing (Full Installation)

❌ **IPS inline blocking**: Rock Pi E not configured yet
❌ **VPN access**: No remote access yet
❌ **T-Pot honeypot**: Not deployed
❌ **Full monitoring**: Missing metricbeat, UPS monitoring, etc.
❌ **Backup system**: No automated backups
❌ **DNS server**: Using router DNS instead of BIND

## Next Steps

### Option A: Continue with Full Installation

Follow [Installation Guide](installation-guide.md) for complete setup.

**Recommended order**:
1. Configure VPN (WireGuard) - 1 hour
2. Setup Rock Pi E (IPS) - 2 hours
3. Configure T-Pot Honeypot - 2 hours
4. Setup BIND DNS - 1 hour
5. Configure NAS shares - 1 hour
6. Setup backup system - 1 hour
7. Install monitoring agents - 1 hour
8. Configure dashboards - 1 hour

### Option B: Improve Current Setup

1. **Better VLAN configuration**
   - Configure proper VLANs on switch
   - Update router firewall rules
   - See: [Network Design](network-design.md)

2. **Add more data sources**
   - Install Metricbeat for system metrics
   - Configure router syslog forwarding
   - Add more Filebeat inputs

3. **Tune Suricata**
   - Update rules: `sudo suricata-update`
   - Add custom rules
   - Adjust performance settings

4. **Create Dashboards**
   - Import dashboard templates
   - Customize visualizations
   - Set up alerts

## Common Quick Fixes

### Kibana Shows No Data

```bash
# Check if Filebeat is sending data
sudo filebeat test output

# Manually create test data
curl -X POST "http://192.168.20.10:9200/test-index/_doc" -H 'Content-Type: application/json' -d'
{
  "@timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
  "message": "test"
}'

# Check in Kibana Discover
```

### Elasticsearch Won't Start

```bash
# Check logs
podman logs elasticsearch

# Most common: vm.max_map_count
sudo sysctl -w vm.max_map_count=262144

# Restart
podman restart elasticsearch
```

### Suricata Not Alerting

```bash
# Test with EICAR
curl http://www.eicar.org/download/eicar.com.txt

# Check alerts
sudo tail -f /var/log/suricata/fast.log

# If no alerts, update rules
sudo suricata-update
sudo systemctl restart suricata
```

## Testing Your Setup

### Generate Test Traffic

```bash
# HTTP request
curl http://192.168.20.10

# DNS query
nslookup google.com 192.168.20.53

# Generate alerts (safe test)
curl http://testmynids.org/uid/index.html
```

### View in Kibana

1. Open Kibana: https://192.168.20.10:443
2. Navigate to **Discover**
3. Select time range: Last 15 minutes
4. Search for: `event_type:alert`

## Performance Expectations

With this quick setup:

- **Latency**: No additional latency (no inline IPS)
- **CPU (Server)**: 20-30% average
- **RAM (Server)**: 10-15GB used (Elasticsearch + Kibana)
- **Disk**: ~1-5GB per day (depending on traffic)

## Quick Reference

### Essential URLs

- Kibana: https://192.168.20.10:443
- Elasticsearch: http://192.168.20.10:9200
- Router: http://192.168.20.1
- Switch: http://192.168.20.11

### Essential Commands

```bash
# Check services
podman ps
sudo systemctl status suricata
sudo systemctl status filebeat

# View logs
podman logs -f elasticsearch
sudo tail -f /var/log/suricata/fast.log

# Restart services
podman restart elasticsearch kibana
sudo systemctl restart suricata
```

### Default Credentials

- OpenWrt: root / (password you set)
- HP Switch: manager / (default or password you set)
- Kibana: No authentication (internal network only!)

## Security Notes

⚠️ **This quick setup is for internal/lab use**

For production:
- Enable Elasticsearch authentication
- Configure firewall rules properly
- Set up VPN for remote access
- Use HTTPS with proper certificates
- Change all default passwords

## Getting Stuck?

1. Check [Troubleshooting Guide](troubleshooting.md)
2. Review logs (see Essential Commands above)
3. Verify network connectivity
4. Check [Architecture Documentation](architecture.md)

## Estimated Costs

**Time to Quick Setup**: 30 minutes
**Time to Full Setup**: 8-12 hours
**Electricity**: ~50-100W continuous ($5-10/month)
**Equivalent Cloud Cost**: $300-1500/month

## What You've Learned

After this quick start, you now have:
- Working ELK Stack
- Network traffic visibility
- Centralized logging
- Foundation for full security monitoring

Continue to [Installation Guide](installation-guide.md) for complete setup.
