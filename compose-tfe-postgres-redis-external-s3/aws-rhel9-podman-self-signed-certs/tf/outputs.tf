output "tfe_url" {
  description = "TFE URL"
  value       = "https://${var.tfe_hostname}"
}

output "tfe_hostname" {
  description = "TFE hostname"
  value       = var.tfe_hostname
}

output "tfe_eip" {
  description = "TFE Elastic IP address"
  value       = aws_eip.tfe.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.tfe.id
}

output "etc_hosts_entry" {
  description = "Entry to add to /etc/hosts on your laptop"
  value       = "${aws_eip.tfe.public_ip} ${var.tfe_hostname}"
}

output "setup_instructions" {
  description = "Instructions to access TFE"
  value       = <<-EOT
    1. Run the post-install script to configure your laptop:
       ./post-install.sh

       This will:
       - Add ${aws_eip.tfe.public_ip} ${var.tfe_hostname} to /etc/hosts
       - Install TLS certificate to system trust store

    2. Wait for userdata to complete (sudo cat /var/log/cloud-init-output.log)

    3. Access TFE at: https://${var.tfe_hostname}
  EOT
}
