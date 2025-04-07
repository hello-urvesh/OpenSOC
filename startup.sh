#!/bin/bash

set -e

apt-get update -y
apt-get upgrade -y
apt-get install -y docker.io curl jq openssl

curl -SL https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /opt/OpenSOC/vol/{thehive,cortex,elasticsearch}
cd /opt/OpenSOC

CORTEX_API_KEY=$(openssl rand -hex 32)

cat <<EOF > vol/cortex/application.conf
play.http.secret.key="CortexTestPassword"

search {
  index = cortex
  uri = "http://elasticsearch:9200"
}

cache.job = 10 minutes

job {
  runner = [docker, process]
}

analyzer.urls = ["https://download.thehive-project.org/analyzers.json"]
responder.urls = ["https://download.thehive-project.org/responders.json"]
auth {
  providers = [local]
}
auth.local.admin {
  type = "basic"
  login = "admin"
  password = "$CORTEX_API_KEY"
}
EOF

cat <<EOF > vol/thehive/application.conf
play.http.secret.key="TheHiveTestPassword"

db.janusgraph {
  storage.backend: berkeleyje
  storage.directory: /opt/thp/thehive/db
  berkeleyje.freeDisk: 200
  index.search.backend: lucene
  index.search.directory: /opt/thp/thehive/index
}

storage {
  provider: localfs
  localfs.location: /opt/thp/thehive/data
}

play.http.parser.maxDiskBuffer: 50MB

play.modules.enabled += org.thp.thehive.connector.cortex.CortexModule
cortex.servers = [{
  name = "local"
  url = "http://cortex:9001"
  auth {
    type = "bearer"
    key = "$CORTEX_API_KEY"
  }
}]
cortex.refreshDelay = 5 seconds
cortex.maxRetryOnError = 3
cortex.statusCheckInterval = 30 seconds

notification.webhook.endpoints = [{
  name: "local"
  url: "http://localhost:5678/"
  version: 0
  wsConfig: {}
  auth: {type: "none"}
  includedTheHiveOrganisations: ["*"]
  excludedTheHiveOrganisations: []
}]
EOF

cat <<EOF > docker-compose.yml
version: '3.8'

services:
  elasticsearch:
    image: elasticsearch:7.11.1
    container_name: elasticsearch
    restart: unless-stopped
    ports:
      - "9200:9200"
    environment:
      - http.host=0.0.0.0
      - discovery.type=single-node
      - cluster.name=hive
      - script.allowed_types=inline
      - thread_pool.search.queue_size=100000
      - thread_pool.write.queue_size=10000
      - gateway.recover_after_nodes=1
      - xpack.security.enabled=false
      - bootstrap.memory_lock=true
      - ES_JAVA_OPTS=-Xms2g -Xmx2g
    volumes:
      - ./vol/elasticsearch/data:/usr/share/elasticsearch/data
      - ./vol/elasticsearch/logs:/usr/share/elasticsearch/logs

  cortex:
    image: thehiveproject/cortex:latest
    container_name: cortex
    restart: unless-stopped
    command: --job-directory /tmp/cortex-jobs
    volumes:
      - ./vol/cortex/application.conf:/etc/cortex/application.conf
      - /tmp/cortex-jobs:/tmp/cortex-jobs
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - elasticsearch
    ports:
      - "9001:9001"

  thehive:
    image: thehiveproject/thehive4:latest
    container_name: thehive
    restart: unless-stopped
    command: --no-config --no-config-secret
    volumes:
      - ./vol/thehive/application.conf:/etc/thehive/application.conf
      - ./vol/thehive/db:/opt/thp/thehive/db
      - ./vol/thehive/data:/opt/thp/thehive/data
      - ./vol/thehive/index:/opt/thp/thehive/index
    depends_on:
      - elasticsearch
      - cortex
    ports:
      - "9000:9000"
EOF

docker-compose up -d
