variable "region" {
  description = "Region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "minio_allowed_ip" {
  description = "IP Address allowed to access MinIO"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "The instance type for the EC2 instance"
  type        = string
  default     = "t2.micro"
}

variable "resource_prefix" {
  description = "Prefix for MinIO S3 resources created"
  type        = string
  default     = "ec2-minio"
}

variable "minio_s3_api_port" {
  description = "The port for MinIO S3 API"
  type        = number
  default     = 80
}

variable "minio_console_port" {
  description = "The port for MinIO Console (web UI)"
  type        = number
  default     = 9001
}

variable "minio_s3_access_key" {
  description = "S3 access key for MinIO"
  type        = string
}

variable "minio_s3_secret_key" {
  description = "S3 secret key for MinIO"
  type        = string
  sensitive   = true
}

variable "minio_default_bucket" {
  description = "Default bucket to create in MinIO"
  type        = string
  default     = "default-bucket"
}
