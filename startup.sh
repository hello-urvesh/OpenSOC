#!/bin/bash
set -e

echo "[START] Fully automated TheHive + Cortex setup"

# Install Docker using Docker's official apt repo (production method)
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin jq

# Start Docker
systemctl enable docker
systemctl start docker

# Setup OpenSOC directory
BASE_DIR="/root/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch}
cd ${BASE_DIR}

# Fix permissions so elasticsearch doesn't die
chown -R 1000:1000 ${BASE_DIR}/vol/elasticsearch

# Pull docker-compose.yml from GitHub
curl -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/main/docker-compose.yml

# Create TheHive config file with placeholder key
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

# Start containers
docker compose up -d

# Wait for Elasticsearch to become healthy
echo "[INFO] Waiting for Elasticsearch..."
until curl -s http://localhost:9200 | grep -q "cluster_name"; do
  sleep 5
  echo "[INFO] Still waiting for Elasticsearch..."
done

# Wait for Cortex to start
echo "[INFO] Waiting for Cortex..."
until curl -s http://localhost:9001 | grep -q "Cortex"; do
  sleep 5
  echo "[INFO] Still waiting for Cortex..."
done

# Generate Cortex API key
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

# Inject Cortex key into TheHive config
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# Restart TheHive with updated config
docker compose restart thehive

echo "[DONE] Deployed TheHive + Cortex 🎉"
