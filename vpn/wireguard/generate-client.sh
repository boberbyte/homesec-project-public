#!/bin/bash

# WireGuard Client Generator for HomeSec
# This script generates WireGuard client configurations

set -e

# Configuration
SERVER_PUBLIC_KEY="YOUR_SERVER_PUBLIC_KEY"
SERVER_ENDPOINT="YOUR_PUBLIC_IP_OR_HOSTNAME:51820"
VPN_NETWORK="10.10.100"
DNS_SERVER="192.168.20.53"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage
usage() {
    echo "Usage: $0 <client-name> <client-ip-last-octet>"
    echo ""
    echo "Example: $0 laptop 2"
    echo "  This will create laptop-wg0.conf with IP 10.10.100.2"
    echo ""
    echo "Available IPs: 2-50 (1 is reserved for server)"
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    usage
fi

CLIENT_NAME=$1
CLIENT_IP_OCTET=$2
CLIENT_IP="${VPN_NETWORK}.${CLIENT_IP_OCTET}"

# Validate IP octet
if [ "$CLIENT_IP_OCTET" -lt 2 ] || [ "$CLIENT_IP_OCTET" -gt 50 ]; then
    echo -e "${RED}Error: IP octet must be between 2 and 50${NC}"
    exit 1
fi

# Check if WireGuard tools are installed
if ! command -v wg &> /dev/null; then
    echo -e "${RED}Error: WireGuard tools not installed${NC}"
    echo "Install with: sudo apt install wireguard-tools (or brew install wireguard-tools on macOS)"
    exit 1
fi

# Generate keys
echo -e "${GREEN}Generating keys for ${CLIENT_NAME}...${NC}"
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# Create config file
CONFIG_FILE="${CLIENT_NAME}-wg0.conf"
echo -e "${GREEN}Creating configuration file: ${CONFIG_FILE}${NC}"

cat > "$CONFIG_FILE" <<EOF
# WireGuard Client Configuration
# Device: ${CLIENT_NAME}
# IP: ${CLIENT_IP}/24
# Generated: $(date)

[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/24
DNS = ${DNS_SERVER}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_ENDPOINT}
AllowedIPs = 192.168.20.0/24
PersistentKeepalive = 25
EOF

echo -e "${GREEN}Configuration file created: ${CONFIG_FILE}${NC}"
echo ""

# Generate QR code if qrencode is available
if command -v qrencode &> /dev/null; then
    echo -e "${GREEN}Generating QR code for mobile devices...${NC}"
    qrencode -t ansiutf8 < "$CONFIG_FILE"
    echo ""
    qrencode -o "${CLIENT_NAME}-wg0.png" < "$CONFIG_FILE"
    echo -e "${GREEN}QR code saved as: ${CLIENT_NAME}-wg0.png${NC}"
    echo ""
else
    echo -e "${YELLOW}Note: Install qrencode to generate QR codes for mobile devices${NC}"
    echo "  Ubuntu/Debian: sudo apt install qrencode"
    echo "  macOS: brew install qrencode"
    echo ""
fi

# Display peer configuration for server
echo -e "${YELLOW}======================================${NC}"
echo -e "${YELLOW}Add this to OpenWrt router:${NC}"
echo -e "${YELLOW}======================================${NC}"
echo ""
echo "config wireguard_vpn"
echo "    option public_key '${CLIENT_PUBLIC_KEY}'"
echo "    option description '${CLIENT_NAME}'"
echo "    list allowed_ips '${CLIENT_IP}/32'"
echo "    option persistent_keepalive '25'"
echo ""
echo -e "${YELLOW}Then restart network on router:${NC}"
echo "  /etc/init.d/network restart"
echo ""

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Client Information:${NC}"
echo -e "${GREEN}======================================${NC}"
echo "Client Name: ${CLIENT_NAME}"
echo "Client IP: ${CLIENT_IP}/24"
echo "Public Key: ${CLIENT_PUBLIC_KEY}"
echo "Config File: ${CONFIG_FILE}"
echo ""

echo -e "${YELLOW}To connect (Linux/macOS):${NC}"
echo "  sudo wg-quick up ${CONFIG_FILE}"
echo ""
echo -e "${YELLOW}To disconnect:${NC}"
echo "  sudo wg-quick down ${CLIENT_NAME}-wg0"
echo ""

echo -e "${YELLOW}For mobile devices:${NC}"
echo "  Scan the QR code with WireGuard app"
echo ""

echo -e "${GREEN}Done!${NC}"
