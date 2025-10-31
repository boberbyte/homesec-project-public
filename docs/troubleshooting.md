# HomeSec - Troubleshooting Guide

## Quick Diagnostics

### Check All Services Status

```bash
# On CentOS Server
sudo systemctl status elasticsearch
sudo systemctl status kibana
sudo systemctl status named  # BIND DNS
sudo systemctl status smb  # Samba
sudo systemctl status nfs-server
podman ps

# On Rock Pi E (IPS)
sudo systemctl status suricata
brctl show
ip addr

# On Rock Pi 4 SE (IDS)
sudo systemctl status suricata
sudo systemctl status filebeat
sudo systemctl status metricbeat

# On OpenWrt Router (via SSH)
wg show
iptables -L -v -n | head -20
cat /tmp/dhcp.leases
logread | tail -50
```

## Network Issues

### No Internet Access

**Symptoms**: Cannot reach external websites

**Diagnosis**:
```bash
# From any client
ping 8.8.8.8  # Test internet
ping 192.168.20.1  # Test router

# On OpenWrt router
ping -I eth0 8.8.8.8  # Test WAN
ip route show  # Check default route
```

**Solutions**:
1. Check WAN cable connection
2. Verify ISP connection
3. Check OpenWrt WAN interface: `ip link show eth0`
4. Check NAT rules: `iptables -t nat -L -v -n`
5. Restart networking: `/etc/init.d/network restart`

### Cannot Access VLAN

**Symptoms**: Cannot ping devices in another VLAN

**Diagnosis**:
```bash
# From client
ping 192.168.20.10  # Server
ping 192.168.10.100  # Trusted VLAN
ping 192.168.30.10  # IoT VLAN

# Check routing
ip route show

# On OpenWrt router
iptables -L -v -n | grep <vlan>
```

**Solutions**:
1. Check VLAN configuration on HP switch
2. Verify firewall rules on OpenWrt
3. Check if traffic is being blocked: `logread | grep firewall`
4. Verify VLAN interfaces: `ip -d link show`

### SPAN Port Not Working

**Symptoms**: Rock Pi 4 SE IDS sees no traffic

**Diagnosis**:
```bash
# On Rock Pi 4 SE
sudo tcpdump -i eth0 -c 100
# Should see mirrored traffic from all switch ports

# On HP Switch (via console)
show mirror
```

**Solutions**:
1. Verify SPAN configuration on HP switch
2. Check port 22 is configured as SPAN destination
3. Ensure source ports are correct
4. Restart switch if needed
5. Check cable connection to Rock Pi 4 SE

## IPS/IDS Issues

### Rock Pi E IPS Not Blocking

**Symptoms**: Malicious traffic not being blocked

**Diagnosis**:
```bash
# On Rock Pi E
sudo systemctl status suricata
sudo tail -f /var/log/suricata/fast.log

# Check if running in IPS mode
ps aux | grep suricata | grep "af-packet"

# Check bridge
brctl show
```

**Solutions**:
1. Verify Suricata is running in IPS mode (not IDS)
2. Check suricata.yaml: `copy-mode: ips`
3. Verify bridge is up: `brctl show`
4. Check rules are loaded: `suricatasc -c "reload-rules"`
5. Test with EICAR: `curl http://www.eicar.org/download/eicar.com.txt`
6. Check action-order in suricata.yaml (drop should be before alert)

### High CPU on Rock Pi E

**Symptoms**: Rock Pi E CPU usage >80%

**Diagnosis**:
```bash
# On Rock Pi E
htop
top -H  # Show threads

# Check Suricata stats
sudo suricatasc -c "dump-counters"
```

**Solutions**:
1. Reduce worker threads in suricata.yaml
2. Disable unused protocols in app-layer
3. Reduce rule set (disable unnecessary rules)
4. Check for packet drops: `ethtool -S eth0`
5. Increase ring buffer size in suricata.yaml

### Suricata Not Logging

**Symptoms**: No alerts in /var/log/suricata/

**Diagnosis**:
```bash
# Check if Suricata is running
sudo systemctl status suricata

# Check logs directory permissions
ls -la /var/log/suricata/

# Check suricata.yaml outputs section
grep -A 20 "outputs:" /etc/suricata/suricata.yaml
```

**Solutions**:
1. Check directory permissions: `sudo chown -R suricata:suricata /var/log/suricata`
2. Verify EVE log is enabled in suricata.yaml
3. Check disk space: `df -h`
4. Restart Suricata: `sudo systemctl restart suricata`

## ELK Stack Issues

### Elasticsearch Won't Start

**Symptoms**: Container exits immediately or won't start

**Diagnosis**:
```bash
# Check logs
podman logs elasticsearch

# Check if port is in use
sudo netstat -tulpn | grep 9200

# Check system settings
sysctl vm.max_map_count
```

**Solutions**:
1. Increase vm.max_map_count:
   ```bash
   sudo sysctl -w vm.max_map_count=262144
   echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
   ```

2. Reduce heap size in docker-compose.yml:
   ```yaml
   ES_JAVA_OPTS=-Xms4g -Xmx4g
   ```

3. Check disk space: `df -h`

4. Check permissions:
   ```bash
   sudo chown -R 1000:1000 /opt/homesec/server/elk-stack/elasticsearch/data
   ```

### Kibana Not Accessible

**Symptoms**: Cannot access https://192.168.20.10:443

**Diagnosis**:
```bash
# Check if Kibana is running
podman ps | grep kibana

# Check Kibana logs
podman logs kibana

# Test from server
curl http://localhost:443/api/status

# Test Elasticsearch connection
podman exec -it kibana curl http://elasticsearch:9200
```

**Solutions**:
1. Wait 2-3 minutes for Kibana to initialize
2. Check Elasticsearch is running: `curl http://localhost:9200`
3. Restart Kibana: `podman restart kibana`
4. Check firewall: `sudo firewall-cmd --list-all`
5. Verify VPN connection if accessing remotely

### No Data in Kibana

**Symptoms**: Index patterns created but no data visible

**Diagnosis**:
```bash
# Check if indices exist
curl http://192.168.20.10:9200/_cat/indices?v

# Check document count
curl http://192.168.20.10:9200/_count?pretty

# Check if Filebeat is sending data
sudo systemctl status filebeat
sudo filebeat test output
```

**Solutions**:
1. Verify Filebeat is running on Rock Pi 4 SE
2. Check Filebeat config: `sudo filebeat test config`
3. Check Elasticsearch connection: `sudo filebeat test output`
4. Verify index patterns match actual indices
5. Check time range in Kibana (last 15 minutes vs last 7 days)
6. Manually send test event:
   ```bash
   curl -X POST "http://192.168.20.10:9200/test-index/_doc" -H 'Content-Type: application/json' -d'
   {
     "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
     "message": "test"
   }'
   ```

### Elasticsearch Disk Full

**Symptoms**: Cannot index new documents, errors in logs

**Diagnosis**:
```bash
# Check disk usage
df -h /opt/homesec/server/elk-stack/

# Check index sizes
curl http://192.168.20.10:9200/_cat/indices?v&h=index,store.size&s=store.size:desc
```

**Solutions**:
1. Delete old indices:
   ```bash
   curl -X DELETE http://192.168.20.10:9200/homesec-ips-2024.01.01
   ```

2. Configure ILM to auto-delete old data

3. Force merge old indices:
   ```bash
   curl -X POST "http://192.168.20.10:9200/homesec-*/_forcemerge?max_num_segments=1"
   ```

4. Move data to larger disk

## VPN Issues

### Cannot Connect to VPN

**Symptoms**: WireGuard client cannot establish connection

**Diagnosis**:
```bash
# On client
sudo wg show

# On OpenWrt router
wg show
netstat -uln | grep 51820
iptables -L -v -n | grep 51820
```

**Solutions**:
1. Verify UDP port 51820 is reachable:
   ```bash
   nc -u -v <your-public-ip> 51820
   ```

2. Check firewall allows WireGuard:
   ```bash
   # On OpenWrt
   iptables -L -v -n | grep 51820
   ```

3. Verify client config has correct:
   - Server public key
   - Server endpoint (public IP:51820)
   - Allowed IPs

4. Check system time is synchronized (both client and server)

5. Restart WireGuard:
   ```bash
   # On OpenWrt
   /etc/init.d/network restart
   ```

### VPN Connected but No Access

**Symptoms**: VPN connects but cannot access resources

**Diagnosis**:
```bash
# On client
ip route show  # Check routes
ping 192.168.20.1  # Test router
ping 192.168.20.10  # Test server

# On OpenWrt router
iptables -L -v -n | grep vpn
```

**Solutions**:
1. Check routing on client
2. Verify firewall allows VPN → Infrastructure:
   ```bash
   # On OpenWrt
   iptables -L -v -n | grep 10.10.100
   ```

3. Check AllowedIPs in client config includes 192.168.20.0/24

4. Test specific service:
   ```bash
   curl https://192.168.20.10:443  # Kibana
   ```

## DNS Issues

### DNS Not Resolving

**Symptoms**: Cannot resolve homesec.local domains

**Diagnosis**:
```bash
# Test DNS resolution
nslookup server.homesec.local 192.168.20.53
dig @192.168.20.53 kibana.homesec.local

# Check if BIND is running
sudo systemctl status named

# Check DNS logs
sudo journalctl -u named -n 50
```

**Solutions**:
1. Check BIND is running: `sudo systemctl start named`
2. Verify firewall allows DNS (port 53)
3. Check BIND config: `sudo named-checkconf`
4. Check zone files: `sudo named-checkzone homesec.local /etc/named/zones/homesec.local.zone`
5. Restart BIND: `sudo systemctl restart named`

## T-Pot Honeypot Issues

### T-Pot Not Receiving Attacks

**Symptoms**: No honeypot data in Kibana

**Diagnosis**:
```bash
# On T-Pot VM
sudo docker ps  # Check if honeypots are running
sudo docker logs <container>

# Check firewall port forwards
# On OpenWrt router
iptables -t nat -L -v -n | grep 192.168.99.10
```

**Solutions**:
1. Verify port forwarding rules on OpenWrt
2. Check T-Pot services are running: `sudo docker ps`
3. Check VLAN 99 connectivity: `ping 192.168.99.10`
4. Verify firewall allows honeypot → Elasticsearch
5. Check T-Pot logs: `sudo docker-compose logs`

### T-Pot Can Access Internal Network

**Symptoms**: Security issue - honeypot should be isolated

**Diagnosis**:
```bash
# From T-Pot VM
ping 192.168.10.100  # Should FAIL
ping 192.168.20.1    # Should FAIL (except DNS/ELK)

# On OpenWrt router
iptables -L -v -n | grep honeypot
```

**Solutions**:
1. Review firewall rules on OpenWrt
2. Ensure VLAN 99 is properly isolated
3. Only allow:
   - 192.168.99.10 → 192.168.20.10:9200 (Elasticsearch)
   - 192.168.99.10 → 192.168.20.53:53 (DNS)
4. Block all other inter-VLAN traffic

## Performance Issues

### Slow Network Performance

**Symptoms**: Network throughput lower than expected

**Diagnosis**:
```bash
# Test throughput
iperf3 -c 192.168.20.10

# Check Rock Pi E CPU
# (console or SSH to Rock Pi E)
htop

# Check for packet drops
ethtool -S eth0 | grep drop
ethtool -S eth1 | grep drop
```

**Solutions**:
1. Tune Rock Pi E Suricata (reduce workers, disable features)
2. Check for duplex mismatch: `ethtool eth0`
3. Disable hardware offloading if causing issues
4. Consider bypassing IPS temporarily to isolate issue

### High Server CPU/RAM Usage

**Symptoms**: Server sluggish, services slow

**Diagnosis**:
```bash
# On CentOS server
htop
iotop  # Check disk I/O
iftop  # Check network I/O

# Check specific services
podman stats

# Check Elasticsearch heap
curl http://192.168.20.10:9200/_nodes/stats/jvm?pretty
```

**Solutions**:
1. Tune Elasticsearch heap size
2. Reduce Elasticsearch index refresh interval
3. Configure ILM to delete old indices
4. Check for runaway VMs: `virsh list`
5. Review resource allocation to VMs

## General Debugging

### Get Component Logs

```bash
# OpenWrt Router
logread
logread -f  # Follow

# CentOS Server
sudo journalctl -xe
sudo journalctl -u named -f  # Follow specific service

# Podman Containers
podman logs elasticsearch
podman logs kibana -f  # Follow

# Rock Pi Systems
sudo journalctl -xe
sudo systemctl status suricata -l

# Suricata
sudo tail -f /var/log/suricata/suricata.log
sudo tail -f /var/log/suricata/fast.log
```

### Network Packet Capture

```bash
# Capture on specific interface
sudo tcpdump -i eth0 -w /tmp/capture.pcap

# Capture specific traffic
sudo tcpdump -i eth0 port 443  # HTTPS traffic
sudo tcpdump -i eth0 host 192.168.20.10  # Traffic to/from server

# Read capture
tcpdump -r /tmp/capture.pcap
wireshark /tmp/capture.pcap  # If GUI available
```

### Test Connectivity Matrix

```bash
# Create test script
cat > test-connectivity.sh <<'EOF'
#!/bin/bash
echo "Testing connectivity from $(hostname)..."
echo ""
echo "Internet:"
ping -c 2 8.8.8.8 && echo "✓ Internet OK" || echo "✗ Internet FAIL"
echo ""
echo "Router:"
ping -c 2 192.168.20.1 && echo "✓ Router OK" || echo "✗ Router FAIL"
echo ""
echo "Server:"
ping -c 2 192.168.20.10 && echo "✓ Server OK" || echo "✗ Server FAIL"
echo ""
echo "DNS:"
nslookup server.homesec.local 192.168.20.53 >/dev/null 2>&1 && echo "✓ DNS OK" || echo "✗ DNS FAIL"
echo ""
echo "Elasticsearch:"
curl -s http://192.168.20.10:9200 >/dev/null && echo "✓ Elasticsearch OK" || echo "✗ Elasticsearch FAIL"
echo ""
echo "Kibana:"
curl -s http://192.168.20.10:443/api/status >/dev/null && echo "✓ Kibana OK" || echo "✗ Kibana FAIL"
EOF

chmod +x test-connectivity.sh
./test-connectivity.sh
```

## Getting Help

### Collect Diagnostic Information

```bash
# Create diagnostic report
cat > diagnostic-report.txt <<EOF
HomeSec Diagnostic Report
Generated: $(date)

=== System Information ===
$(uname -a)
$(cat /etc/os-release)

=== Network Configuration ===
$(ip addr show)
$(ip route show)

=== Service Status ===
$(systemctl status elasticsearch kibana named --no-pager)
$(podman ps)

=== Disk Usage ===
$(df -h)

=== Memory Usage ===
$(free -h)

=== Recent Errors ===
$(journalctl -p err -n 50 --no-pager)
EOF

cat diagnostic-report.txt
```

### Community Resources

- Suricata: https://forum.suricata.io/
- Elastic: https://discuss.elastic.co/
- OpenWrt: https://forum.openwrt.org/
- WireGuard: https://lists.zx2c4.com/mailman/listinfo/wireguard

### Common Commands Reference

```bash
# Restart all services
sudo systemctl restart named smb nfs-server
podman-compose -f /opt/homesec/server/elk-stack/docker-compose.yml restart

# Check all logs
sudo journalctl -xe
podman logs elasticsearch
podman logs kibana

# Network troubleshooting
ping <host>
traceroute <host>
mtr <host>
tcpdump -i <interface>

# Firewall debugging
iptables -L -v -n
firewall-cmd --list-all

# Performance monitoring
htop
iotop
iftop
nethogs
```
