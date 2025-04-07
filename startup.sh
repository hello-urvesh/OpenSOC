#!/bin/bash
set -e

echo "[START] Startup script running..."

# Update system and install dependencies
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get install -y docker.io curl jq openssl

# Start Docker
systemctl enable docker
systemctl start docker

# Set up directories
USER=$(whoami)
BASE_DIR="/home/${USER}/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch}
cd ${BASE_DIR}

# Download docker-compose.yml from GitHub
curl -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/refs/heads/main/docker-compose.yml

# Start TheHive + Cortex
docker compose up -d

# Wait for Cortex to be up
echo "[INFO] Waiting for Cortex to become ready..."
until curl -s http://localhost:9001 | grep -q "Cortex"; do
    sleep 5
done

# Generate Cortex API key
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

echo "[INFO] Cortex API key: $CORTEX_API_KEY"

# Inject Cortex API key into TheHive config
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# Restart TheHive to load Cortex integration
docker compose restart thehive

echo "[DONE] TheHive and Cortex fully deployed and integrated!"
