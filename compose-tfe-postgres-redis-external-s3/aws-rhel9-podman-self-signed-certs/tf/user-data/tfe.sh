#!/bin/bash
set -euo pipefail

# Install SSM Agent
dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install Podman and required packages
dnf install -y podman podman-docker python3-pip

# Enable and start Podman socket
systemctl enable --now podman.socket

# Install podman-compose
pip3 install podman-compose

# Add /usr/local/bin to PATH permanently
cat > /etc/profile.d/local-bin-path.sh <<'PATH_EOF'
export PATH=/usr/local/bin:$PATH
PATH_EOF
chmod 644 /etc/profile.d/local-bin-path.sh

# Add to current session PATH
export PATH=/usr/local/bin:$PATH

# Configure Podman registries for short-name resolution
cat > /etc/containers/registries.conf.d/shortnames.conf <<'REGISTRIES_EOF'
unqualified-search-registries = ["docker.io"]
REGISTRIES_EOF

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
    image: docker.io/library/postgres:15
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
    image: docker.io/library/redis:7-alpine
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
      - "443:8443"
      - "80:8080"
    environment:
      TFE_HOSTNAME: $${TFE_HOSTNAME}
      TFE_HTTP_PORT: 8080
      TFE_HTTPS_PORT: 8443
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
        bind:
          selinux: z
      - type: bind
        source: /run/podman/podman.sock
        target: /var/run/docker.sock
        bind:
          selinux: z
      - type: volume
        source: tfe_data
        target: /var/lib/terraform-enterprise
      - type: tmpfs
        target: /var/log/terraform-enterprise
        tmpfs:
          size: 1073741824
      - type: tmpfs
        target: /run
        tmpfs:
          size: 1073741824
      - type: tmpfs
        target: /tmp
        tmpfs:
          size: 1073741824
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      tfe_network:
        aliases:
          - $${TFE_HOSTNAME}
    restart: unless-stopped
    cap_add:
      - IPC_LOCK
    security_opt:
      - label=type:spc_t

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

# Podman login to HashiCorp registry
echo "${tfe_license}" | podman login --username terraform images.releases.hashicorp.com --password-stdin

# Pull TFE image
podman pull images.releases.hashicorp.com/hashicorp/terraform-enterprise:${tfe_version}

# Start services using podman-compose
cd "$WORK_DIR"
podman-compose up -d

# Wait for TFE to be ready
sleep 300

# Get IACT token
IACT_TOKEN=$(podman exec tfe tfectl admin token 2>/dev/null || echo "TFE not ready yet")

echo "=================================================="
echo "TFE Setup Complete!"
echo "=================================================="
echo "TFE URL: https://${tfe_hostname}"
echo "IACT Token: $IACT_TOKEN"
echo "=================================================="
