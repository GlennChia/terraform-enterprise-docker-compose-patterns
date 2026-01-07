output "minio_s3_endpoint" {
  description = "MinIO S3 API endpoint"
  value       = "http://${aws_instance.minio.public_ip}:${var.minio_s3_api_port}"
}

output "minio_console_endpoint" {
  description = "MinIO Console (web UI) endpoint"
  value       = "http://${aws_instance.minio.public_ip}:${var.minio_console_port}"
}

output "minio_s3_access_key" {
  description = "S3 access key for MinIO"
  value       = var.minio_s3_access_key
}

output "minio_s3_secret_key" {
  description = "S3 secret key for MinIO"
  value       = nonsensitive(var.minio_s3_secret_key)
}

output "minio_default_bucket" {
  description = "Default bucket created in MinIO"
  value       = var.minio_default_bucket
}

output "minio_instance_id" {
  description = "EC2 instance ID for MinIO"
  value       = aws_instance.minio.id
}

output "minio_public_ip" {
  description = "Public IP address of MinIO EC2 instance"
  value       = aws_instance.minio.public_ip
}

output "test_commands_go" {
  description = "Commands to test MinIO with the Go SDK test script"
  value = nonsensitive(<<-EOT
    # First time setup: Install dependencies and generate go.sum
    cd ../go-validate && go mod tidy

    # Option 1: Run directly with go run
    go run test-s3-sdk.go \
      "http://${aws_instance.minio.public_ip}:${var.minio_s3_api_port}" \
      "${var.minio_s3_access_key}" \
      "${nonsensitive(var.minio_s3_secret_key)}"

    # Option 2: Build and run
    go build -o test-s3-sdk test-s3-sdk.go
    ./test-s3-sdk \
      "http://${aws_instance.minio.public_ip}:${var.minio_s3_api_port}" \
      "${var.minio_s3_access_key}" \
      "${nonsensitive(var.minio_s3_secret_key)}"

    # Option 3: Using environment variables
    export MINIO_ENDPOINT="http://${aws_instance.minio.public_ip}:${var.minio_s3_api_port}"
    export MINIO_ACCESS_KEY="${var.minio_s3_access_key}"
    export MINIO_SECRET_KEY="${nonsensitive(var.minio_s3_secret_key)}"
    go run test-s3-sdk.go
  EOT
  )
}
