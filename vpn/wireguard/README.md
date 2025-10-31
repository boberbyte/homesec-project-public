# WireGuard VPN Configuration

## Overview

WireGuard provides secure remote access to the HomeSec management network (VLAN 20 - Infrastructure).

**Key Features**:
- Modern, fast, and secure VPN protocol
- UDP port 51820 (only exposed port to internet)
- Access to Infrastructure VLAN only (security restriction)
- Support for multiple clients (laptop, phone, tablet, etc.)

## Server Configuration

### Server Details

**Server IP**: 10.10.100.1/24
**Listen Port**: 51820 (UDP)
**Endpoint**: Your public IP or DDNS hostname

### Generate Server Keys

On OpenWrt router:

```bash
# SSH to router
ssh root@192.168.20.1

# Create directory for keys
mkdir -p /etc/wireguard
cd /etc/wireguard

# Generate private and public keys
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

# View keys
cat server_private.key
cat server_public.key
```

### Add Server Configuration to OpenWrt

```bash
# Edit network config
nano /etc/config/network

# Find the VPN interface section and add the private key:
config interface 'vpn'
    option proto 'wireguard'
    option private_key 'PASTE_SERVER_PRIVATE_KEY_HERE'
    option listen_port '51820'
    list addresses '10.10.100.1/24'

# Restart network
/etc/init.d/network restart
```

## Client Configuration

### Client 1: Laptop

#### Generate Client Keys

On your laptop (Linux/Mac):

```bash
# Install WireGuard
# Ubuntu/Debian: sudo apt install wireguard-tools
# macOS: brew install wireguard-tools
# Windows: Download from wireguard.com

# Generate keys
wg genkey | tee laptop_private.key | wg pubkey > laptop_public.key

# View public key (needed for server config)
cat laptop_public.key
```

#### Add Client to OpenWrt Server

On OpenWrt router:

```bash
# Edit network config
nano /etc/config/network

# Add peer configuration
config wireguard_vpn
    option public_key 'PASTE_LAPTOP_PUBLIC_KEY_HERE'
    option description 'Laptop'
    list allowed_ips '10.10.100.2/32'
    option persistent_keepalive '25'

# Restart network
/etc/init.d/network restart
```

#### Create Client Config File

Create file `laptop-wg0.conf`:

```ini
[Interface]
# Client private key
PrivateKey = PASTE_LAPTOP_PRIVATE_KEY_HERE

# Client IP in VPN network
Address = 10.10.100.2/24

# DNS server (HomeSec BIND server)
DNS = 192.168.20.53

[Peer]
# Server public key
PublicKey = PASTE_SERVER_PUBLIC_KEY_HERE

# Endpoint (your public IP or DDNS hostname)
Endpoint = YOUR_PUBLIC_IP:51820

# Allow all traffic through VPN (full tunnel)
# Or specify only management networks: 192.168.20.0/24
AllowedIPs = 192.168.20.0/24

# Keep connection alive (important for NAT)
PersistentKeepalive = 25
```

#### Connect from Laptop

```bash
# Linux/Mac
sudo wg-quick up laptop-wg0

# Check status
sudo wg show

# Test connectivity
ping 192.168.20.1  # Router
ping 192.168.20.10 # Server
curl https://kibana.homesec.local  # Kibana

# Disconnect
sudo wg-quick down laptop-wg0
```

### Client 2: Phone (iOS/Android)

#### Generate Client Keys

On OpenWrt router:

```bash
# Generate keys for phone
cd /etc/wireguard
wg genkey | tee phone_private.key | wg pubkey > phone_public.key

# View keys
cat phone_private.key
cat phone_public.key
```

#### Add Phone to OpenWrt Server

```bash
# Edit network config
nano /etc/config/network

# Add peer
config wireguard_vpn
    option public_key 'PASTE_PHONE_PUBLIC_KEY_HERE'
    option description 'Phone'
    list allowed_ips '10.10.100.3/32'
    option persistent_keepalive '25'

# Restart network
/etc/init.d/network restart
```

#### Create Phone Config

Create file `phone-wg0.conf`:

```ini
[Interface]
PrivateKey = PASTE_PHONE_PRIVATE_KEY_HERE
Address = 10.10.100.3/24
DNS = 192.168.20.53

[Peer]
PublicKey = PASTE_SERVER_PUBLIC_KEY_HERE
Endpoint = YOUR_PUBLIC_IP:51820
AllowedIPs = 192.168.20.0/24
PersistentKeepalive = 25
```

#### Generate QR Code for Phone

On a computer:

```bash
# Install qrencode
# Ubuntu/Debian: sudo apt install qrencode
# macOS: brew install qrencode

# Generate QR code
qrencode -t ansiutf8 < phone-wg0.conf

# Or save as image
qrencode -o phone-wg0.png < phone-wg0.conf
```

Scan QR code with WireGuard app on phone (iOS/Android).

### Client 3: Tablet

Follow same process as phone, use IP `10.10.100.4/32`.

## IP Assignment Table

| Device | IP | Description |
|--------|-----|-------------|
| Server | 10.10.100.1 | OpenWrt Router (VPN endpoint) |
| Laptop | 10.10.100.2 | Personal laptop |
| Phone | 10.10.100.3 | Mobile phone |
| Tablet | 10.10.100.4 | Tablet |
| Work Laptop | 10.10.100.5 | Work laptop |
| Reserved | 10.10.100.6-50 | Future clients |

## Firewall Configuration

VPN clients can ONLY access VLAN 20 (Infrastructure).

**Allowed**:
- SSH to server (192.168.20.10:22)
- Kibana (192.168.20.10:443)
- Switch management (192.168.20.11:80/443)
- Router management (192.168.20.1:80/443)
- DNS (192.168.20.53:53)

**Blocked**:
- VLAN 10 (Trusted LAN)
- VLAN 30 (IoT/Guest)
- VLAN 40 (Lab VMs)
- VLAN 99 (Honeypot)

This restriction is enforced by firewall rules in OpenWrt.

## Testing VPN

### From VPN Client

```bash
# Connect VPN
sudo wg-quick up laptop-wg0

# Test 1: Ping router
ping 192.168.20.1

# Test 2: Ping server
ping 192.168.20.10

# Test 3: Access Kibana
curl -k https://192.168.20.10:443

# Test 4: SSH to server
ssh user@192.168.20.10

# Test 5: Access switch web UI
curl -k https://192.168.20.11

# Test 6: DNS resolution
nslookup kibana.homesec.local 192.168.20.53

# Test 7: Verify VLAN isolation (should fail)
ping 192.168.10.100  # Trusted LAN - should timeout
ping 192.168.99.10   # Honeypot - should timeout
```

### On OpenWrt Server

```bash
# Check WireGuard status
wg show

# Expected output:
# interface: vpn
#   public key: <server_public_key>
#   private key: (hidden)
#   listening port: 51820
#
# peer: <laptop_public_key>
#   endpoint: <client_public_ip>:<client_port>
#   allowed ips: 10.10.100.2/32
#   latest handshake: 30 seconds ago
#   transfer: 12.34 KiB received, 56.78 KiB sent

# Check active connections
netstat -uln | grep 51820

# Check firewall logs for VPN traffic
logread | grep vpn
```

## Security Best Practices

### Key Management

1. **Never share private keys**
2. **Store keys securely** (password manager, encrypted disk)
3. **Rotate keys quarterly**
4. **Revoke compromised keys immediately**

### Revoke a Client

If a device is lost/stolen:

```bash
# SSH to router
ssh root@192.168.20.1

# Edit network config
nano /etc/config/network

# Delete the peer section for that device
# (or comment it out)

# Restart network
/etc/init.d/network restart

# Verify
wg show
```

### Key Rotation

Rotate keys every 3-6 months:

```bash
# Generate new server keys
wg genkey | tee server_private_new.key | wg pubkey > server_public_new.key

# Update server config with new private key
nano /etc/config/network

# Update all client configs with new server public key

# Restart network
/etc/init.d/network restart
```

## Troubleshooting

### Cannot Connect to VPN

```bash
# On client, check if WireGuard is running
sudo wg show

# Check if port 51820 is reachable
nc -u -v YOUR_PUBLIC_IP 51820

# On server, check if WireGuard is listening
netstat -uln | grep 51820

# Check firewall
iptables -L -v -n | grep 51820
```

### Connected but No Access

```bash
# Check routing on client
ip route show

# Should see route to 192.168.20.0/24 via VPN

# Check if packets reaching server
# On OpenWrt:
tcpdump -i vpn

# Check firewall rules
iptables -L -v -n | grep vpn
```

### Slow Performance

```bash
# Check MTU (should be 1420 for WireGuard)
ip link show wg0

# Test throughput
iperf3 -c 192.168.20.10

# Check latency
ping -c 100 192.168.20.10
```

### Handshake Issues

```bash
# Check system time (must be synchronized)
date

# Check if keys are correct
wg show

# Enable debug logging
wg set wg0 private-key /path/to/key
```

## Monitoring

### Metrics to Collect

- Active VPN connections
- Bandwidth per client
- Connection duration
- Failed connection attempts
- Handshake failures

### Integration with ELK

WireGuard logs are sent to ELK Stack via syslog:

```bash
# On OpenWrt, enable verbose logging
logread | grep wireguard
```

Filebeat on Rock Pi 4 SE collects these logs and sends to Elasticsearch.

## Dynamic DNS (if using dynamic public IP)

If you don't have a static IP:

```bash
# Install ddns scripts on OpenWrt
opkg install luci-app-ddns ddns-scripts

# Configure DDNS provider (DuckDNS, No-IP, etc.)
# Use your DDNS hostname in client configs instead of IP
```

Example client config with DDNS:

```ini
[Peer]
PublicKey = <server_public_key>
Endpoint = yourhostname.duckdns.org:51820
AllowedIPs = 192.168.20.0/24
PersistentKeepalive = 25
```

## Client Configuration Templates

All client config templates are in the `configs/` directory:

```
vpn/wireguard/configs/
├── client-template.conf      # Generic template
├── laptop-example.conf        # Laptop example
├── phone-example.conf         # Phone example
└── README.md                  # Client-specific instructions
```

## Useful Commands

```bash
# Server (OpenWrt)
wg show                        # Show VPN status
wg show vpn                    # Show specific interface
wg set vpn peer <pubkey> remove  # Remove peer
/etc/init.d/network restart    # Restart VPN

# Client
wg-quick up wg0               # Connect
wg-quick down wg0             # Disconnect
wg show                        # Show status
wg show wg0 latest-handshakes  # Show handshake times
wg show wg0 transfer           # Show bandwidth

# Key generation
wg genkey                      # Generate private key
wg pubkey                      # Derive public key from private
wg genpsk                      # Generate pre-shared key (optional)
```

## Related Documentation

- [OpenWrt Configuration](../../network/openwrt/README.md)
- [Network Design](../../docs/network-design.md)
- [Architecture](../../docs/architecture.md)
- Official WireGuard docs: https://www.wireguard.com/quickstart/
