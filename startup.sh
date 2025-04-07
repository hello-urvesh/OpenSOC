#!/bin/bash
set -e

echo "[START] Fully automated TheHive + Cortex setup"

# ------------------------------
# STEP 1: Install Docker Engine + Compose Plugin
# ------------------------------
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

# Start Docker and enable on boot
systemctl enable docker
systemctl start docker

# ------------------------------
# STEP 2: Set up OpenSOC project folder
# ------------------------------
BASE_DIR="/root/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch}
cd ${BASE_DIR}

# Fix ownership for Elasticsearch volume (run container as UID 1000 inside)
chown -R 1000:1000 ${BASE_DIR}/vol/elasticsearch

# ------------------------------
# STEP 3: Pull docker-compose.yml
# ------------------------------
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/main/docker-compose.yml

# ------------------------------
# STEP 4: Create TheHive application.conf
# ------------------------------
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

# ------------------------------
# STEP 5: Start containers
# ------------------------------
docker compose up -d

# ------------------------------
# STEP 6: Wait for Cortex to fully start
# ------------------------------
echo "[INFO] Waiting for Cortex to be ready..."
until curl -s http://localhost:9001 | grep -q "Cortex"; do
  echo "[INFO] Waiting for Cortex..."
  sleep 5
done

# ------------------------------
# STEP 7: Generate Cortex API token
# ------------------------------
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

# ------------------------------
# STEP 8: Inject token into TheHive config
# ------------------------------
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# ------------------------------
# STEP 9: Restart TheHive with real token
# ------------------------------
docker compose restart thehive

echo "[DONE] ✅ TheHive + Cortex successfully deployed 🎉"
