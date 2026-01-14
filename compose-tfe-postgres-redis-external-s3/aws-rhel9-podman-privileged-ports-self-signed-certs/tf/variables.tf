variable "region" {
  description = "Region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "tfe_allowed_ip" {
  description = "IP Address allowed to access TFE"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "The instance type for the EC2 instance"
  type        = string
  default     = "m5.large"
}

variable "resource_prefix" {
  description = "Prefix for TFE resources created"
  type        = string
  default     = "ec2-tfe"
}

# TFE Configuration
variable "tfe_version" {
  description = "TFE version to deploy"
  type        = string
  default     = "1.1.2"
}

variable "tfe_hostname" {
  description = "Hostname for TFE"
  type        = string
  default     = "tfe.ec2"
}

variable "tfe_license" {
  description = "TFE license key"
  type        = string
  sensitive   = true
}

variable "tfe_encryption_password" {
  description = "Encryption password for TFE"
  type        = string
  sensitive   = true
}

# Database Configuration
variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "tfeadmin"
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
  default     = "tfe"
}

# Redis Configuration
variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
}

# S3 Configuration
variable "s3_endpoint" {
  description = "S3 endpoint URL"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name"
  type        = string
}

variable "s3_region" {
  description = "S3 region"
  type        = string
  default     = "us-east-1"
}

variable "s3_access_key" {
  description = "S3 access key"
  type        = string
  sensitive   = true
}

variable "s3_secret_key" {
  description = "S3 secret key"
  type        = string
  sensitive   = true
}

