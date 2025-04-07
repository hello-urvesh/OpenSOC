#!/bin/bash
set -e

echo "[START] Fully automated TheHive + Cortex setup"

# Update system and install dependencies
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get install -y docker.io curl jq openssl

# Install Docker Compose v1 (since Docker Compose v2 isn't available)
echo "[INFO] Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Set up OpenSOC directory structure
BASE_DIR="/root/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch}
cd ${BASE_DIR}

# Download docker-compose.yml from GitHub
echo "[INFO] Downloading docker-compose.yml..."
curl -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/main/docker-compose.yml

# Create TheHive config file with placeholder for Cortex key
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

# Start TheHive + Cortex stack
echo "[INFO] Starting TheHive + Cortex stack using Docker Compose..."
docker-compose up -d

# Wait for Cortex to become ready
echo "[INFO] Waiting for Cortex to become ready..."
until curl -s http://localhost:9001 | grep -q "Cortex"; do
  sleep 5
done

# Generate Cortex API token
echo "[INFO] Generating Cortex API key..."
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

# Inject Cortex API key into TheHive config
echo "[INFO] Injecting Cortex API key into TheHive config..."
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# Restart TheHive service
echo "[INFO] Restarting TheHive to apply Cortex integration..."
docker-compose restart thehive

echo "[DONE] TheHive + Cortex are fully deployed and integrated 🎉"
