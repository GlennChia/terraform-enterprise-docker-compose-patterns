resource "aws_eip" "tfe" {
  domain = "vpc"

  tags = {
    Name = "${var.resource_prefix}-eip"
  }
}
