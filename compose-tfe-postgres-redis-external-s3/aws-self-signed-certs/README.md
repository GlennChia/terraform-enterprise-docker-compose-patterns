# Terraform Enterprise Docker Compose Setup on AWS with self-signed certs and external S3

This setup deploys Terraform Enterprise v1.1.2 with Docker Compose that includes PostgreSQL and Redis on EC2 using self-signed certificates. Users can pass in environment variables to configure external S3 storage. This allows validation of various S3-compatible object storage options with TFE.

> [!WARNING]
> This setup is intended for **development, testing, and validation purposes only**. It uses self-signed certificates, default passwords, and is not hardened for production environments.

# 1. Architecture

![architecture diagram](./docs/01-architecture/01-architecture-diagram.png)

- EC2 instance created in a public subnet. EC2 installed with Docker Compose. Docker Compose includes TFE, PostgreSQL, and Redis containers
- External S3 is referenced in Docker Compose via environment variables, allowing various S3 object stores to be validated with TFE

# 2. Deployment

Prerequisites

- Set up S3 storage that is publicly accessible. For example, follow the instructions at [external-s3/minio-ec2-public-ip/README.md](../../external-s3/minio-ec2-public-ip/README.md) to deploy publicly accessible MinIO object storage on EC2. Applying the Terraform configurations at [external-s3/minio-ec2-public-ip/tf/](../../external-s3/minio-ec2-public-ip/tf/) outputs values for the S3 endpoint, bucket name, access key, and secret access key that are used in the `.env` file. The screenshot below shows the MinIO UI after deployment.

![s3 home page](./docs/02-deployment/01-pre-req-s3/01-s3-home-page.png)

Step 1: In [tf](./tf/), copy [terraform.tfvars.example](./tf/terraform.tfvars.example) to `terraform.tfvars` and adjust the variables accordingly.

Step 2: In [tf](./tf/) run `terraform init` and `terraform apply --auto-approve`

Step 3: In [tf](./tf/), run the post-install script

```bash
./post-install.sh
```

The script will automatically:

1. **Configure /etc/hosts** - Automatically add `<EC2_PUBLIC_IP> tfe.local` entry
2. **Install certificate to keychain** (macOS only) - Add certificate to System keychain as trusted root

> [!NOTE]
> These steps require administrator privileges and will prompt for your password.

![post install](./docs/02-deployment/02-post-install/01-post-install.png)

# 3. Verify

## 3.1 Self-signed cert added to keychain (Mac)

Verify that the `tfe.ec2` cert is added to the Keychain Access

![cert](./docs/02-deployment/02-post-install/02-cert.png)

## 3.2 tfe.ec2 added to /etc/hosts

Verify that `<EC2_PUBLIC_IP> tfe.ec2` is added to `/etc/hosts`

![etc hosts](./docs/02-deployment/02-post-install/03-etc-hosts.png)

## 3.3 Login to Terraform Enterprise

From the EC2 console, click the checkbox next to the EC2 instance -> Actions -> Monitor and troubleshoot -> Get system log

![ec2 get system log](./docs/02-deployment/03-tfe-login/01-ec2-get-system-log.png)

Copy the `IACT Token`

![system log iact token](./docs/02-deployment/03-tfe-login/02-system-log-iact-token.png)

Enter the admin token in the GUI at `https://tfe.ec2/admin/account/new?token=<IACT_TOKEN>`. This leads to the account creation page. Enter the username, email, and set a password. The password requires a minimum of 10 characters, for example: `P@ssw0rd123`.

![tfe create account](./docs/02-deployment/03-tfe-login/03-tfe-create-account.png)

Once logged in, you will be directed to the Organizations page

![organizations page](./docs/02-deployment/03-tfe-login/04-organizations-page.png)

# 4. Testing

## 4.1 Create organization

Create a new organization named `test-org`.

![create organization](./docs/03-testing/01-create-organization/01-create-organization.png)

## 4.2 Create workspace

Create a new workspace using the `CLI-Driven Workflow`

![organization created](./docs/03-testing/02-create-workspace/01-organization-created.png)

Enter the workspace name as `tfe-test`, leave the rest as defaults and choose `Create`

![configure settings](./docs/03-testing/02-create-workspace/02-create-workspace.png)

Workspace created

![workspace created](./docs/03-testing/02-create-workspace/03-workspace-created.png)

## 4.3 Generate team token

From the organization settings page under `Security`, choose `API tokens`, choose `Team Tokens`, and `Create a team token`.

![team tokens](./docs/03-testing/03-create-token/01-team-tokens.png)

Create a team token under the `owners` team for testing purposes

![create team token](./docs/03-testing/03-create-token/02-create-team-token.png)

Copy the token created

![team token](./docs/03-testing/03-create-token/03-team-token.png)

## 4.4 Configure Terraform and run terraform apply from the CLI

Create a `~/.terraformrc` file with the following content, replacing `xxxxxx.atlasv1.zzzzzzzzzzzzz` with the team token created in the previous step:

```hcl
credentials "tfe.ec2" {
  token = "xxxxxx.atlasv1.zzzzzzzzzzzzz"
}
```

![terraform rc](./docs/03-testing/03-create-token/04-terraform-rc.png)

Run `terraform init` in [tf-cli-test](./tf-cli-test/)

![terraform init](./docs/03-testing/04-terraform-commands/01-apply/01-terraform-init.png)

Run `terraform apply`

![terraform apply](./docs/03-testing/04-terraform-commands/01-apply/02-terraform-apply.png)

Workspace runs shows a run that is `Triggered via CLI` and in the `Planned` state

![tfe workspace runs](./docs/03-testing/04-terraform-commands/01-apply/03-tfe-workspace-runs.png)

Workspace run details shows `Plan finished`

![tfe workspace run details](./docs/03-testing/04-terraform-commands/01-apply/04-tfe-workspace-run-details.png)

S3 bucket contains an `archivistterraform` directory

![s3 bucket](./docs/03-testing/04-terraform-commands/01-apply/05-s3-bucket.png)

The `archivistterraform` directory contains other sub-directories

![s3 archivistterraform](./docs/03-testing/04-terraform-commands/01-apply/06-s3-archivistterraform.png)

Proceed to approve the terraform apply and let the apply complete

![terraform apply complete](./docs/03-testing/04-terraform-commands/02-apply-approve/01-terraform-apply-complete.png)

TFE shows `Apply finished`

![tfe workspace run](./docs/03-testing/04-terraform-commands/02-apply-approve/02-tfe-workspace-run.png)

Verify that the workspace contains the state. Note the state ID.

![tfe workspace states](./docs/03-testing/04-terraform-commands/02-apply-approve/03-tfe-workspace-states.png)

State details

![tfe workspace state details](./docs/03-testing/04-terraform-commands/02-apply-approve/04-tfe-workspace-state-details.png)

The `archivistterraform` directory now contains the `states` sub-directory

![s3 archivistterraform](./docs/03-testing/04-terraform-commands/02-apply-approve/05-s3-archivistterraform.png)

The `states` directory contains the state directory with an ID that matches the state ID in TFE.

![s3 archivistterraform states](./docs/03-testing/04-terraform-commands/02-apply-approve/06-s3-archivistterraform-states.png)

This contains 2 other directories

![s3 archivistterraform state sub dir](./docs/03-testing/04-terraform-commands/02-apply-approve/07-s3-archivistterraform-state-sub-dir.png)

View file in directory 1

![s3 archivistterraform state file1](./docs/03-testing/04-terraform-commands/02-apply-approve/08-s3-archivistterraform-state-file1.png)

View file in directory 2

![s3 archivistterraform state file2](./docs/03-testing/04-terraform-commands/02-apply-approve/09-s3-archivistterraform-state-file2.png)
