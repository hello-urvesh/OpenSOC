#!/bin/bash
set -e

echo "[START] Fully automated TheHive + Cortex + N8N + Wazuh setup"

# Update system & install dependencies
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release jq git

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# Set up base directory
BASE_DIR="/root/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch,n8n,local-files}
mkdir -p ${BASE_DIR}/vol/wazuh/{config,data}

chown -R root:root ${BASE_DIR}/vol
chmod -R 755 ${BASE_DIR}/vol
chown -R 1000:1000 ${BASE_DIR}/vol/elasticsearch
chown -R 1000:1000 ${BASE_DIR}/vol/n8n

# Create logback.xml files
cat <<EOF > ${BASE_DIR}/vol/cortex/logback.xml
<configuration>
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n</pattern>
    </encoder>
  </appender>
  <root level="INFO">
    <appender-ref ref="STDOUT" />
  </root>
</configuration>
EOF

cat <<EOF > ${BASE_DIR}/vol/thehive/logback.xml
<configuration>
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n</pattern>
    </encoder>
  </appender>
  <root level="INFO">
    <appender-ref ref="STDOUT" />
  </root>
</configuration>
EOF

# Download latest docker-compose.yml
cd ${BASE_DIR}
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/main/docker-compose.yml

# TheHive config (uses port 9201 for its ES)
cat <<EOF > ${BASE_DIR}/vol/thehive/application.conf
play.http.secret.key="TheHiveSecretKey"
storage { provider: localfs localfs.location: /opt/thp/thehive/data }
index {
  backend: elasticsearch
  elasticsearch {
    hostname = ["elasticsearch"]
    port = 9200
    index = thehive
  }
}
db.janusgraph { storage.backend: berkeleyje storage.directory: /opt/thp/thehive/db berkeleyje.freeDisk: 200 }
play.modules.enabled += org.thp.thehive.connector.cortex.CortexModule
cortex {
  servers = [
    { name = "Cortex" url = "http://cortex:9001" auth { type = "bearer" key = "__CORTEX_API_KEY__" } }
  ]
}
EOF

# -------------------- WAZUH SETUP BEGINS --------------------
echo "[WAZUH] Cloning Wazuh Docker repo..."
cd ${BASE_DIR}
git clone https://github.com/wazuh/wazuh-docker.git -b v4.11.2
cd ${BASE_DIR}/wazuh-docker/single-node

echo "[WAZUH] Generating certificates using official Wazuh certs-generator..."
docker compose -f generate-indexer-certs.yml run --rm generator

chmod -R 644 ./config/wazuh_indexer_ssl_certs/*
chown -R root:root ./config/wazuh_indexer_ssl_certs/

echo "[WAZUH] Starting Wazuh stack..."
docker compose up -d
# -------------------- WAZUH SETUP ENDS ----------------------

# Start TheHive + Cortex + N8N
cd ${BASE_DIR}
docker compose up -d

# Wait for Cortex to be up
until curl -s http://localhost:9001 | grep -q "Cortex"; do
  echo "[INFO] Waiting for Cortex to be ready..."
  sleep 5
done

# Generate Cortex API key
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

# Inject Cortex API key into TheHive config
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# Restart TheHive
docker compose restart thehive

echo "[DONE] All services deployed and healthy ✅"
