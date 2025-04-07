#!/bin/bash
set -e

echo "[START] Fully automated TheHive + Cortex setup"

# Update and install dependencies
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release jq

# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repo
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker + Compose
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable Docker
systemctl enable docker
systemctl start docker

# Setup project structure
BASE_DIR="/root/OpenSOC"
mkdir -p ${BASE_DIR}/vol/{thehive,cortex,elasticsearch}

# Fix Elasticsearch volume permission
chown -R 1000:1000 ${BASE_DIR}/vol/elasticsearch

# Create placeholder logback.xml for TheHive
cat <<EOF > ${BASE_DIR}/vol/thehive/logback.xml
<configuration>
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%date [%thread] %-5level %logger{36} - %msg%n</pattern>
    </encoder>
  </appender>
  <root level="INFO">
    <appender-ref ref="STDOUT"/>
  </root>
</configuration>
EOF

# Create placeholder logback.xml for Cortex
cat <<EOF > ${BASE_DIR}/vol/cortex/logback.xml
<configuration>
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%date [%thread] %-5level %logger{36} - %msg%n</pattern>
    </encoder>
  </appender>
  <root level="INFO">
    <appender-ref ref="STDOUT"/>
  </root>
</configuration>
EOF

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

# Pull docker-compose.yml
cd ${BASE_DIR}
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/hello-urvesh/OpenSOC/main/docker-compose.yml

# Start containers
docker compose up -d

# Wait for Cortex to be ready
until curl -s http://localhost:9001 | grep -q "Cortex"; do
  echo "[INFO] Waiting for Cortex..."
  sleep 5
done

# Generate Cortex API key
CORTEX_API_KEY=$(curl -s -XPOST http://localhost:9001/api/user/admin/token \
  -H 'Content-Type: application/json' \
  -d '{"password":"secret", "ttl": 0}' | jq -r '.token')

# Inject Cortex key into TheHive config
sed -i "s|__CORTEX_API_KEY__|$CORTEX_API_KEY|g" ${BASE_DIR}/vol/thehive/application.conf

# Restart TheHive
docker compose restart thehive

echo "[DONE] TheHive + Cortex deployed successfully 🎉"
