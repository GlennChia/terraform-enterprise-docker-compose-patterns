# Terraform Enterprise Docker Compose Patterns

Deployment patterns for running Terraform Enterprise using Docker Compose with various configurations and external dependencies.

- [Terraform Enterprise with PostgreSQL, Redis, and External S3](./compose-tfe-postgres-redis-external-s3/local/README.md) - Docker Compose setup for TFE with PostgreSQL, Redis, and external S3 storage for development, testing, and validation
- [MinIO S3 on EC2 with Public IP](./external-s3/minio-ec2-public-ip/README.md) - Terraform configuration for deploying publicly accessible MinIO object storage on EC2 for use as S3-compatible storage with TFE
