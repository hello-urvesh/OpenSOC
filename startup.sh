#!/bin/bash
set -e

echo "[START] Fully automated TheHive + Cortex setup"

# Install Docker using Docker's official apt repo (production recommended method)
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release jq

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker
systemctl enable docker
systemctl start docker

# Setup directory
BASE_DIR="/root/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch}
cd ${BASE_DIR}

# Step 1: Temporary launch containers to extract default logback.xml files
echo "[INFO] Pulling containers to extract logback.xml"
cat <<EOF > docker-compose.temp.yml
version: "3.7"
services:
  thehive:
    image: strangebee/thehive:5.1
    command: tail -f /dev/null
  cortex:
    image: thehiveproject/cortex:3.1
    command: tail -f /dev/null
EOF

docker compose -f docker-compose.temp.yml up -d
sleep 10

# Copy logback.xml from containers
docker cp \$(docker ps -qf "ancestor=strangebee/thehive:5.1"):/etc/thehive/logback.xml ${BASE_DIR}/vol/thehive/logback.xml
docker cp \$(docker ps -qf "ancestor=thehiveproject/cortex:3.1"):/etc/cortex/logback.xml ${BASE_DIR}/vol/cortex/logback.xml

# Cleanup temp containers
docker compose -f docker-compose.temp.yml down
rm docker-compose.temp.yml

# Pull main docker-compose.yml
curl -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/main/docker-compose.yml

# Create application.conf for TheHive
cat <<EOF > ${BASE_DIR}/vol/thehive/application.conf
play.modules.enabled += org.thp.thehive.connector.cortex.CortexConnector
cortex {
  servers = [
    {
      name = "Cortex"
      url = "http://cortex:9001"
      auth {
        type = "bearer"
        key = "__CORTEX_API_KEY__"
      }
    }
  ]
}
EOF

# Final run
echo "[INFO] Running final docker-compose"
docker compose up -d

# Wait for Cortex
until curl -s http://localhost:9001 | grep -q "Cortex"; do
  echo "[INFO] Waiting for Cortex..."
  sleep 5
done

# Generate Cortex API key
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

# Inject into TheHive
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# Restart TheHive
docker compose restart thehive

echo "[DONE] Deployed TheHive + Cortex 🎉"
