#!/bin/bash

# HomeSec - ELK Stack Deployment Script
# This script deploys Elasticsearch and Kibana using Podman

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ELK_DIR="/opt/homesec/server/elk-stack"
BACKUP_DIR="/mnt/raid/backups/elasticsearch"
ES_HEAP_SIZE="16g"  # Adjust based on your RAM

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}HomeSec - ELK Stack Deployment${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo -e "${RED}Please run as root (sudo)${NC}"
   exit 1
fi

# Check if Podman is installed
if ! command -v podman &> /dev/null; then
    echo -e "${RED}Podman is not installed!${NC}"
    echo "Install with: dnf install -y podman podman-compose"
    exit 1
fi

# Check if podman-compose is installed
if ! command -v podman-compose &> /dev/null; then
    echo -e "${YELLOW}podman-compose not found, installing...${NC}"
    dnf install -y podman-compose
fi

# System tuning
echo -e "${GREEN}Configuring system settings...${NC}"

# Set vm.max_map_count
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    sysctl -p
else
    echo "vm.max_map_count already configured"
fi

# Set vm.swappiness
if ! grep -q "vm.swappiness=1" /etc/sysctl.conf; then
    echo "vm.swappiness=1" >> /etc/sysctl.conf
    sysctl -p
else
    echo "vm.swappiness already configured"
fi

# Create directories
echo -e "${GREEN}Creating directories...${NC}"
mkdir -p ${ELK_DIR}/{elasticsearch,kibana,logstash}/{config,data}
mkdir -p ${BACKUP_DIR}

# Create Elasticsearch config
echo -e "${GREEN}Creating Elasticsearch configuration...${NC}"
cat > ${ELK_DIR}/elasticsearch/config/elasticsearch.yml <<EOF
cluster.name: "homesec-cluster"
network.host: 0.0.0.0

# Disable security for internal network
xpack.security.enabled: false

# Paths
path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs
path.repo: ["${BACKUP_DIR}"]

# Discovery
discovery.type: single-node

# Index settings
action.auto_create_index: true

# Performance
indices.memory.index_buffer_size: 30%
EOF

# Create Kibana config
echo -e "${GREEN}Creating Kibana configuration...${NC}"
cat > ${ELK_DIR}/kibana/config/kibana.yml <<EOF
server.name: "HomeSec-Kibana"
server.host: "0.0.0.0"
server.port: 5601

elasticsearch.hosts: ["http://elasticsearch:9200"]

# Monitoring
monitoring.ui.container.elasticsearch.enabled: true

# Disable security warnings
xpack.security.enabled: false
EOF

# Create docker-compose.yml
echo -e "${GREEN}Creating docker-compose configuration...${NC}"
cat > ${ELK_DIR}/docker-compose.yml <<EOF
version: '3.8'

networks:
  elk:
    driver: bridge

volumes:
  elasticsearch-data:
    driver: local
  kibana-data:
    driver: local

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    container_name: elasticsearch
    hostname: elasticsearch
    restart: unless-stopped

    environment:
      - node.name=homesec-es-01
      - cluster.name=homesec-cluster
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms${ES_HEAP_SIZE} -Xmx${ES_HEAP_SIZE}"
      - bootstrap.memory_lock=true
      - xpack.security.enabled=false

    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536

    ports:
      - "9200:9200"
      - "9300:9300"

    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data
      - ${ELK_DIR}/elasticsearch/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro
      - ${BACKUP_DIR}:${BACKUP_DIR}

    networks:
      - elk

    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    container_name: kibana
    hostname: kibana
    restart: unless-stopped

    environment:
      - SERVERNAME=kibana.homesec.local
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - SERVER_HOST=0.0.0.0
      - SERVER_PORT=5601
      - SERVER_NAME=HomeSec-Kibana
      - MONITORING_UI_CONTAINER_ELASTICSEARCH_ENABLED=true

    ports:
      - "443:5601"

    volumes:
      - kibana-data:/usr/share/kibana/data
      - ${ELK_DIR}/kibana/config/kibana.yml:/usr/share/kibana/config/kibana.yml:ro

    networks:
      - elk

    depends_on:
      elasticsearch:
        condition: service_healthy

    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5601/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
EOF

# Set permissions
chown -R 1000:1000 ${ELK_DIR}/elasticsearch/data
chown -R 1000:1000 ${ELK_DIR}/kibana/data

# Configure firewall
echo -e "${GREEN}Configuring firewall...${NC}"
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.20.0/24" port port="9200" protocol="tcp" accept' 2>/dev/null || true
    firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.20.0/24" port port="443" protocol="tcp" accept' 2>/dev/null || true
    firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.100.0/24" port port="443" protocol="tcp" accept' 2>/dev/null || true
    firewall-cmd --reload
else
    echo "firewalld not running, skipping firewall configuration"
fi

# Start services
echo -e "${GREEN}Starting ELK Stack...${NC}"
cd ${ELK_DIR}
podman-compose up -d

# Wait for Elasticsearch
echo -e "${YELLOW}Waiting for Elasticsearch to start (60 seconds)...${NC}"
sleep 60

# Check Elasticsearch
echo -e "${GREEN}Checking Elasticsearch...${NC}"
if curl -s http://localhost:9200 > /dev/null; then
    echo -e "${GREEN}✓ Elasticsearch is running${NC}"
    curl http://localhost:9200
else
    echo -e "${RED}✗ Elasticsearch failed to start${NC}"
    echo "Check logs: podman logs elasticsearch"
    exit 1
fi

# Wait for Kibana
echo -e "${YELLOW}Waiting for Kibana to start (30 seconds)...${NC}"
sleep 30

# Check Kibana
echo -e "${GREEN}Checking Kibana...${NC}"
if curl -s http://localhost:443/api/status > /dev/null; then
    echo -e "${GREEN}✓ Kibana is running${NC}"
else
    echo -e "${YELLOW}⚠ Kibana may still be starting...${NC}"
    echo "Check logs: podman logs kibana"
fi

# Configure snapshot repository
echo -e "${GREEN}Configuring backup repository...${NC}"
curl -X PUT "http://localhost:9200/_snapshot/homesec_backup" -H 'Content-Type: application/json' -d"
{
  \"type\": \"fs\",
  \"settings\": {
    \"location\": \"${BACKUP_DIR}\"
  }
}" || echo -e "${YELLOW}Warning: Could not configure snapshot repository${NC}"

# Create systemd service for auto-start
echo -e "${GREEN}Creating systemd service...${NC}"
cat > /etc/systemd/system/homesec-elk.service <<EOF
[Unit]
Description=HomeSec ELK Stack
Requires=podman.service
After=podman.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${ELK_DIR}
ExecStart=/usr/bin/podman-compose up -d
ExecStop=/usr/bin/podman-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable homesec-elk.service

echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}ELK Stack deployment complete!${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "${GREEN}Access Kibana:${NC}"
echo "  URL: https://192.168.20.10:443"
echo "  (Connect via VPN or from Infrastructure VLAN)"
echo ""
echo -e "${GREEN}Elasticsearch API:${NC}"
echo "  URL: http://192.168.20.10:9200"
echo ""
echo -e "${GREEN}Container status:${NC}"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo -e "${GREEN}Useful commands:${NC}"
echo "  podman-compose ps              # Check status"
echo "  podman-compose logs -f         # View logs"
echo "  podman-compose restart         # Restart services"
echo "  podman-compose down            # Stop services"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Wait 2-3 minutes for Kibana to fully initialize"
echo "  2. Access Kibana and create index patterns"
echo "  3. Configure Filebeat on Rock Pi 4 SE to send logs"
echo "  4. Import dashboards from dashboards/kibana/"
echo ""
