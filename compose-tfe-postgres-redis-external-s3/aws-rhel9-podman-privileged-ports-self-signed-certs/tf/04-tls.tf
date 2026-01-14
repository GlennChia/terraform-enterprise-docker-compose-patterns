resource "tls_private_key" "tfe" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "tfe" {
  private_key_pem = tls_private_key.tfe.private_key_pem

  subject {
    common_name  = "tfe.ec2"
    organization = "HashiCorp"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names    = ["tfe.ec2"]
  ip_addresses = [aws_eip.tfe.public_ip]
}

# Save certificates locally
resource "local_file" "tfe_cert" {
  content  = tls_self_signed_cert.tfe.cert_pem
  filename = "${path.module}/certs/tfe.crt"
}

resource "local_file" "tfe_key" {
  content         = tls_private_key.tfe.private_key_pem
  filename        = "${path.module}/certs/tfe.key"
  file_permission = "0600"
}
