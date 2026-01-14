# Terraform Enterprise Docker Compose Patterns

Deployment patterns for running Terraform Enterprise using Docker Compose with various configurations and external dependencies.

Deployment patterns for TFE

- [Podman compose on AWS EC2 (TFE, PostgreSQL, Redis) with self-signed certs and External S3](./compose-tfe-postgres-redis-external-s3/aws-rhel9-podman-self-signed-certs/README.md). This method doesn't work with CLI workflows that use remote execution. For S3 validation, the test uses a CLI workflow with local execution instead.
- [Podman compose on AWS EC2 (TFE, PostgreSQL, Redis) privileged ports (80, 443) with self-signed certs and External S3](./compose-tfe-postgres-redis-external-s3/aws-rhel9-podman-privileged-ports-self-signed-certs/README.md)
- [Docker compose on AWS EC2 (TFE, PostgreSQL, Redis) with self-signed certs and External S3](./compose-tfe-postgres-redis-external-s3/aws-self-signed-certs/README.md)
- [Docker compose local (TFE, PostgreSQL, Redis) with self-signed certs and External S3](./compose-tfe-postgres-redis-external-s3/local/README.md)

External dependencies

- [MinIO S3 on EC2 with Public IP](./external-s3/minio-ec2-public-ip/README.md) - Terraform configuration for deploying publicly accessible MinIO object storage on EC2 for use as S3-compatible storage with TFE
