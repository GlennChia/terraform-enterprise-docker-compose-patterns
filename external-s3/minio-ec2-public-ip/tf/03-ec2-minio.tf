resource "aws_instance" "minio" {
  ami                         = data.aws_ssm_parameter.al2023_x86.value
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.this.name
  subnet_id                   = aws_subnet.public1.id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.ec2_minio.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # Enforces IMDSv2
  }

  user_data = templatefile(
    "${path.module}/user-data/minio.sh",
    {
      s3_access_key  = var.minio_s3_access_key
      s3_secret_key  = var.minio_s3_secret_key
      default_bucket = var.minio_default_bucket
      s3_api_port    = var.minio_s3_api_port
      console_port   = var.minio_console_port
    }
  )

  tags = {
    Name = "${var.resource_prefix}-minio"
  }
}

resource "aws_security_group" "ec2_minio" {
  name        = "minio-sg"
  description = "Security group for minio EC2"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_minio_s3_port_allowed_ip" {
  security_group_id = aws_security_group.ec2_minio.id
  from_port         = var.minio_s3_api_port
  to_port           = var.minio_s3_api_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.minio_allowed_ip
  description       = "MinIO S3 API port ${var.minio_s3_api_port}"

  tags = {
    Name = "minio-s3-api-${var.minio_s3_api_port}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_minio_console_port_allowed_ip" {
  security_group_id = aws_security_group.ec2_minio.id
  from_port         = var.minio_console_port
  to_port           = var.minio_console_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.minio_allowed_ip
  description       = "MinIO Console port ${var.minio_console_port}"

  tags = {
    Name = "minio-console-${var.minio_console_port}"
  }
}

resource "aws_vpc_security_group_egress_rule" "egress_all" {
  security_group_id = aws_security_group.ec2_minio.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound"

  tags = {
    Name = "all"
  }
}

