terraform {
  cloud {
    hostname     = "tfe.ec2"
    organization = "test-org"

    workspaces {
      name = "tfe-test"
    }
  }
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}