#!/bin/bash
set -euo pipefail

# Install Docker
dnf install -y docker
systemctl enable docker
systemctl start docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create working directory
WORK_DIR="/opt/tfe"
mkdir -p "$WORK_DIR/certs"
cd "$WORK_DIR"

# Write TLS certificates
cat > "$WORK_DIR/certs/tfe.crt" <<'CERT_EOF'
${tls_cert}
CERT_EOF

cat > "$WORK_DIR/certs/tfe.key" <<'KEY_EOF'
${tls_key}
KEY_EOF

chmod 644 "$WORK_DIR/certs/tfe.key"
chmod 644 "$WORK_DIR/certs/tfe.crt"

# Create .env file
cat > "$WORK_DIR/.env" <<'ENV_EOF'
TFE_VERSION=${tfe_version}

POSTGRES_USER=${postgres_user}
POSTGRES_PASSWORD=${postgres_password}
POSTGRES_DB=${postgres_db}

REDIS_PASSWORD=${redis_password}

TFE_HOSTNAME=${tfe_hostname}

TFE_ENCRYPTION_PASSWORD=${tfe_encryption_password}

TFE_LICENSE=${tfe_license}

S3_ENDPOINT=${s3_endpoint}
S3_BUCKET_NAME=${s3_bucket_name}
S3_REGION=${s3_region}
S3_ACCESS_KEY=${s3_access_key}
S3_SECRET_KEY=${s3_secret_key}
ENV_EOF

# Create docker-compose.yml
cat > "$WORK_DIR/docker-compose.yml" <<'COMPOSE_EOF'
services:
  postgres:
    image: postgres:15
    container_name: tfe-postgres
    environment:
      POSTGRES_USER: $${POSTGRES_USER}
      POSTGRES_PASSWORD: $${POSTGRES_PASSWORD}
      POSTGRES_DB: $${POSTGRES_DB}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - tfe_network
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: tfe-redis
    command: redis-server --requirepass $${REDIS_PASSWORD}
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - tfe_network
    restart: unless-stopped

  tfe:
    image: images.releases.hashicorp.com/hashicorp/terraform-enterprise:$${TFE_VERSION}
    container_name: tfe
    ports:
      - "443:443"
      - "80:80"
    environment:
      TFE_HOSTNAME: $${TFE_HOSTNAME}
      TFE_HTTP_PORT: 80
      TFE_HTTPS_PORT: 443
      TFE_IACT_SUBNETS: "0.0.0.0/0"

      TFE_DATABASE_HOST: postgres:5432
      TFE_DATABASE_NAME: $${POSTGRES_DB}
      TFE_DATABASE_USER: $${POSTGRES_USER}
      TFE_DATABASE_PASSWORD: $${POSTGRES_PASSWORD}
      TFE_DATABASE_PARAMETERS: "sslmode=disable"

      TFE_REDIS_HOST: redis:6379
      TFE_REDIS_PASSWORD: $${REDIS_PASSWORD}
      TFE_REDIS_USE_TLS: "false"
      TFE_REDIS_USE_AUTH: "true"

      TFE_OBJECT_STORAGE_TYPE: "s3"
      TFE_OBJECT_STORAGE_S3_USE_INSTANCE_PROFILE: "false"
      TFE_OBJECT_STORAGE_S3_BUCKET: $${S3_BUCKET_NAME}
      TFE_OBJECT_STORAGE_S3_ENDPOINT: $${S3_ENDPOINT}
      TFE_OBJECT_STORAGE_S3_REGION: $${S3_REGION}
      TFE_OBJECT_STORAGE_S3_ACCESS_KEY_ID: $${S3_ACCESS_KEY}
      TFE_OBJECT_STORAGE_S3_SECRET_ACCESS_KEY: $${S3_SECRET_KEY}

      TFE_TLS_CERT_FILE: /etc/ssl/private/terraform-enterprise/tfe.crt
      TFE_TLS_KEY_FILE: /etc/ssl/private/terraform-enterprise/tfe.key
      TFE_TLS_CA_BUNDLE_FILE: /etc/ssl/private/terraform-enterprise/tfe.crt

      TFE_LICENSE: $${TFE_LICENSE}
      TFE_ENCRYPTION_PASSWORD: $${TFE_ENCRYPTION_PASSWORD}

      TFE_CAPACITY_CONCURRENCY: "10"
      TFE_CAPACITY_MEMORY: "512"

      TFE_OPERATIONAL_MODE: "external"
      TFE_RUN_PIPELINE_DOCKER_NETWORK: "tfe_tfe_network"

    volumes:
      - type: bind
        source: ./certs
        target: /etc/ssl/private/terraform-enterprise
      - type: bind
        source: /var/run/docker.sock
        target: /var/run/docker.sock
      - type: volume
        source: tfe_data
        target: /var/lib/terraform-enterprise
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      tfe_network:
        aliases:
          - tfe.ec2
    restart: unless-stopped
    cap_add:
      - IPC_LOCK

networks:
  tfe_network:
    driver: bridge

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  tfe_data:
    driver: local
COMPOSE_EOF

# Docker login to HashiCorp registry
echo "${tfe_license}" | docker login --username terraform images.releases.hashicorp.com --password-stdin

# Pull TFE image
docker pull images.releases.hashicorp.com/hashicorp/terraform-enterprise:${tfe_version}

# Start Docker Compose services
docker-compose up -d

# Wait for TFE to be ready
sleep 300

# Get IACT token
IACT_TOKEN=$(docker exec tfe tfectl admin token 2>/dev/null || echo "TFE not ready yet")

echo "=================================================="
echo "TFE Setup Complete!"
echo "=================================================="
echo "TFE URL: https://${tfe_hostname}"
echo "IACT Token: $IACT_TOKEN"
echo "=================================================="
