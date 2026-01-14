resource "aws_instance" "tfe" {
  ami                         = data.aws_ami.rhel_9.id
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.this.name
  subnet_id                   = aws_subnet.public1.id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.ec2_tfe.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # Enforces IMDSv2
  }

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile(
    "${path.module}/user-data/tfe.sh",
    {
      tls_cert                = tls_self_signed_cert.tfe.cert_pem
      tls_key                 = tls_private_key.tfe.private_key_pem
      tfe_version             = var.tfe_version
      tfe_hostname            = var.tfe_hostname
      tfe_license             = var.tfe_license
      tfe_encryption_password = var.tfe_encryption_password
      postgres_user           = var.postgres_user
      postgres_password       = var.postgres_password
      postgres_db             = var.postgres_db
      redis_password          = var.redis_password
      s3_endpoint             = var.s3_endpoint
      s3_bucket_name          = var.s3_bucket_name
      s3_region               = var.s3_region
      s3_access_key           = var.s3_access_key
      s3_secret_key           = var.s3_secret_key
    }
  )

  tags = {
    Name = "${var.resource_prefix}-tfe"
  }
}

resource "aws_security_group" "ec2_tfe" {
  name        = "tfe-sg"
  description = "Security group for tfe EC2"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_tfe_https" {
  security_group_id = aws_security_group.ec2_tfe.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.tfe_allowed_ip
  description       = "TFE HTTPS port 443"

  tags = {
    Name = "tfe-https"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_tfe_http_metrics" {
  security_group_id = aws_security_group.ec2_tfe.id
  from_port         = 9090
  to_port           = 9090
  ip_protocol       = "tcp"
  cidr_ipv4         = var.tfe_allowed_ip
  description       = "TFE HTTP Metrics port 9090"

  tags = {
    Name = "tfe-metrics-http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_tfe_https_metrics" {
  security_group_id = aws_security_group.ec2_tfe.id
  from_port         = 9091
  to_port           = 9091
  ip_protocol       = "tcp"
  cidr_ipv4         = var.tfe_allowed_ip
  description       = "TFE HTTPs Metrics port 9091"

  tags = {
    Name = "tfe-metrics-https"
  }
}

resource "aws_vpc_security_group_egress_rule" "egress_all" {
  security_group_id = aws_security_group.ec2_tfe.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound"

  tags = {
    Name = "all"
  }
}

resource "aws_eip_association" "tfe" {
  instance_id   = aws_instance.tfe.id
  allocation_id = aws_eip.tfe.id
}

