#!/bin/bash
set -e

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Create data directory
mkdir -p /mnt/data

# Install Docker
dnf install -y docker
systemctl enable docker
systemctl start docker

# Run MinIO container
docker run -d \
  --name minio \
  --restart=always \
  -p ${s3_api_port}:9000 \
  -p ${console_port}:9001 \
  -e MINIO_ROOT_USER=${s3_access_key} \
  -e MINIO_ROOT_PASSWORD=${s3_secret_key} \
  -v /mnt/data:/data \
  minio/minio:RELEASE.2025-09-07T16-13-09Z server /data --console-address ":9001"

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
for i in {1..30}; do
  if curl -sf http://localhost:${s3_api_port}/minio/health/ready &>/dev/null; then
    echo "MinIO is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

# Install MinIO client
curl -sLo /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x /usr/local/bin/mc

# Configure mc with the correct endpoint
/usr/local/bin/mc alias set local http://localhost:${s3_api_port} ${s3_access_key} ${s3_secret_key}

# Create default bucket
/usr/local/bin/mc mb local/${default_bucket} || true

# Set bucket to public read/write access
/usr/local/bin/mc anonymous set public local/${default_bucket}

# Get public IP
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Print deployment info
echo "================================"
echo "MinIO S3 Gateway is ready!"
echo "================================"
echo "S3 API Endpoint: http://$${PUBLIC_IP}:${s3_api_port}"
echo "Console: http://$${PUBLIC_IP}:${console_port}"
echo "Access Key: ${s3_access_key}"
echo "Secret Key: ${s3_secret_key}"
echo "Default Bucket: ${default_bucket}"
echo "================================"
echo "WARNING: This setup allows public write access!"
echo "================================"

# Save deployment info to log file
cat > /var/log/minio-s3-info.txt <<EOF
MinIO S3 Gateway Information
============================
S3 API Endpoint: http://$${PUBLIC_IP}:${s3_api_port}
Console URL: http://$${PUBLIC_IP}:${console_port}
Access Key: ${s3_access_key}
Secret Key: ${s3_secret_key}
Default Bucket: ${default_bucket}

Note: This is a demo setup with public write access enabled.
You can access the web console at port ${console_port} for GUI management.
EOF

chmod 600 /var/log/minio-s3-info.txt
