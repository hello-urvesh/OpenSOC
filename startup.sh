#!/bin/bash
set -e

echo "[START] Fully automated TheHive + Cortex + N8N setup"

# Update and install dependencies
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release jq

# Add Docker’s official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker engine and Docker Compose plugin
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Set up project directory and fix permissions
BASE_DIR="/root/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch,n8n,local-files}
chown -R root:root ${BASE_DIR}/vol
chmod -R 755 ${BASE_DIR}/vol

# Fix permissions for Elasticsearch and N8N
chown -R 1000:1000 ${BASE_DIR}/vol/elasticsearch
chown -R 1000:1000 ${BASE_DIR}/vol/n8n

# Add logback.xml for Cortex
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

# Add logback.xml for TheHive
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

cd ${BASE_DIR}

# Download latest docker-compose.yml
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/main/docker-compose.yml

# Create TheHive application.conf
cat <<EOF > ${BASE_DIR}/vol/thehive/application.conf
play.http.secret.key="TheHiveSecretKey"

storage {
  provider: localfs
  localfs.location: /opt/thp/thehive/data
}

index {
  backend: elasticsearch
  elasticsearch {
    hostname = ["elasticsearch"]
    index = thehive
  }
}

db.janusgraph {
  storage.backend: berkeleyje
  storage.directory: /opt/thp/thehive/db
  berkeleyje.freeDisk: 200
}

play.modules.enabled += org.thp.thehive.connector.cortex.CortexModule

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

# Wait for Cortex to be ready
until curl -s http://localhost:9001 | grep -q "Cortex"; do
  echo "[INFO] Waiting for Cortex to be ready..."
  sleep 5
done

# Generate Cortex API key
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

# Inject Cortex key
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# Restart TheHive to apply Cortex integration
docker compose restart thehive

echo "[DONE] TheHive + Cortex + N8N deployed successfully 🎉"
