# Terraform Enterprise Docker Compose Setup with external S3

This setup deploys Terraform Enterprise v1.1.2 with Docker Compose that includes PostgreSQL and Redis. Users can pass in environment variables to configure external S3 storage. This allows validation of various S3-compatible object storage options with TFE.

> [!WARNING]
> This setup is intended for **development, testing, and validation purposes only**. It uses self-signed certificates, default passwords, and is not hardened for production environments.

# 1. Architecture

![architecture diagram](./docs/01-architecture/01-architecture-diagram.png)

- Docker Compose includes TFE, PostgreSQL, and Redis containers
- External S3 is referenced in Docker Compose via environment variables, allowing various S3 object stores to be validated with TFE

# 2. Deployment

Prerequisites

- Set up S3 storage that is publicly accessible. For example, follow the instructions at [external-s3/minio-ec2-public-ip/README.md](../../external-s3/minio-ec2-public-ip/README.md) to deploy publicly accessible MinIO object storage on EC2. Applying the Terraform configurations at [external-s3/minio-ec2-public-ip/tf/](../../external-s3/minio-ec2-public-ip/tf/) outputs values for the S3 endpoint, bucket name, access key, and secret access key that are used in the `.env` file. The screenshot below shows the MinIO UI after deployment.

![s3 home page](./docs/02-deployment/01-pre-req-s3/01-s3-home-page.png)

Step 1:  Copy [.env.example](.env.example) to `.env` and adjust the variables accordingly.

Step 2: Run the setup script. The setup script automates the entire TFE environment setup. The script is idempotent, meaning it skips steps that are already completed (e.g., if certificates exist or the hosts entry is present), making it safe to run multiple times.

```bash
./setup.sh
```

The script will automatically:

1. **Verify prerequisites** - Check for Docker, Docker Compose, jq, and .env file
2. **Load environment variables** - Import configuration from .env file (including `TFE_VERSION`)
3. **Authenticate Docker** - Log in to HashiCorp container registry with the TFE license defined in the `.env` file
4. **Show available versions** - Display the latest TFE versions from the registry

![setup1](./docs/02-deployment/02-setup/01-setup1.png)

5. **Pull TFE image** - Download the TFE image you specify (defaults to `TFE_VERSION` from .env or 1.1.2)
6. **Update .env file** - Automatically update `TFE_VERSION` in .env with the version you selected
7. **Generate TLS certificates** - Create self-signed certificates in `certs/` directory
   - Certificate: `certs/tfe.crt`
   - Private Key: `certs/tfe.key`
   - Valid for 365 days with SANs for tfe.local, localhost, and 127.0.0.1

![setup2](./docs/02-deployment/02-setup/02-setup2.png)

8. **Install certificate to keychain** (macOS only) - Add certificate to System keychain as trusted root
9. **Configure /etc/hosts** - Automatically add `127.0.0.1 tfe.local` entry

> [!NOTE]
> Steps 8 and 9 of the script require administrator privileges and will prompt for your password.

![setup4](./docs/02-deployment/02-setup/04-setup4.png)

Step 3: The [docker-compose.yml](./docker-compose.yml) file automatically uses the `TFE_VERSION` from your `.env` file, so no manual image tag updates are needed since the [./setup.sh](./setup.sh) updates the `.env` file.

```bash
docker-compose up
```

![docker compose](./docs/02-deployment/03-docker-compose/01-docker-compose.png)

- Start PostgreSQL and wait until healthy
- Start Redis and wait until healthy
- Start Terraform Enterprise with all dependencies

# 3. Verify

## 3.1 Self-signed cert added to keychain (Mac)

Verify that the `tfe.local` cert is added to the Keychain Access

![cert](./docs/02-deployment/02-setup/05-cert.png)

## 3.2 tfe.local added to /etc/hosts

Verify that `127.0.0.1 tfe.local` is added to `/etc/hosts`

![etc hosts](./docs/02-deployment/02-setup/06-etc-hosts.png)

## 3.3 Login to Terraform Enterprise

Get the Initial Admin Creation Token (IACT):

```bash
docker exec tfe tfectl admin token
```

![get admin token](./docs/02-deployment/04-tfe-login/01-get-admin-token.png)

Enter the admin token in the GUI at `https://tfe.local/admin/account/new?token=<IACT_TOKEN>`. This leads to the account creation page. Enter the username, email, and set a password. The password requires a minimum of 10 characters, for example: `P@ssw0rd123`.

![tfe create account](./docs/02-deployment/04-tfe-login/02-tfe-create-account.png)

Once logged in, you will be directed to the Organizations page

![organizations page](./docs/02-deployment/04-tfe-login/03-organizations-page.png)

# 4. Testing

## 4.1 Create organization

Create a new organization named `test-org`.

![create organization](./docs/03-testing/01-create-organization/01-create-organization.png)

## 4.2 Create workspace

Create a new workspace using the `CLI-Driven Workflow`

![create a new workspace](./docs/03-testing/02-create-workspace/01-create-a-new-workspace.png)

Enter the workspace name as `tfe-test`, leave the rest as defaults and choose `Create`

![configure settings](./docs/03-testing/02-create-workspace/02-configure-settings.png)

Workspace created

![workspace created](./docs/03-testing/02-create-workspace/03-workspace-created.png)

In the workspace settings, set `Execution Mode` to `Local (custom)`

![workspace general settings](./docs/03-testing/02-create-workspace/04-workspace-general-settings.png)

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
credentials "tfe.local" {
  token = "xxxxxx.atlasv1.zzzzzzzzzzzzz"
}
```

![terraform rc](./docs/03-testing/03-create-token/04-terraform-rc.png)

Run `terraform init` in [tf-cli-test](./tf-cli-test/)

![terraform init](./docs/03-testing/04-terraform-commands/01-terraform-init.png)

Run `terraform apply`

![terraform apply](./docs/03-testing/04-terraform-commands/02-terraform-apply.png)

At this point, an `archivistterraform` path is created in the S3 object storage

![archivistterraform](./docs/03-testing/04-terraform-commands/03-archivistterraform.png)

This path eventually contains a file

![archivistterraform slugs file](./docs/03-testing/04-terraform-commands/07-archivistterraform-slugs-file.png)

Proceed to approve the terraform apply

![terraform apply approve](./docs/03-testing/04-terraform-commands/09-terraform-apply-approve.png)

Verify that the workspace contains the state with the ID `sv-SjgKV5a3XgwGRYvc`

![workspace states](./docs/03-testing/04-terraform-commands/10-workspace-states.png)

State details

![state details](./docs/03-testing/04-terraform-commands/11-state-details.png)

Additionally, run `terraform state list` to show that the resources managed by state can be viewed locally

![terraform state list](./docs/03-testing/04-terraform-commands/12-terraform-state-list.png)

After the terraform apply, the `archivistterraform` path contains a `states` path

![archivistterraform states](./docs/03-testing/04-terraform-commands/14-archivistterraform-states.png)

Within the `states` path there is an ID that matches the ID seen in the workspace state

![archivistterraform states sub dir](./docs/03-testing/04-terraform-commands/15-archivistterraform-states-sub-dir.png)

Within this path there are 2 further sub directories

![archivistterraform states sub dir sub dir](./docs/03-testing/04-terraform-commands/16-archivistterraform-states-sub-dir-sub-dir.png)

Each of these sub directories contain their own files

![archivistterraform states sub dir sub dir state file1](./docs/03-testing/04-terraform-commands/17-archivistterraform-states-sub-dir-sub-dir-state-file1.png)

![archivistterraform states sub dir sub dir state file2](./docs/03-testing/04-terraform-commands/19-archivistterraform-states-sub-dir-sub-dir-state-file2.png)

# 5. Cleanup

Step 1: Stop services and remove volumes. This will delete all PostgreSQL data, Redis cache, and TFE data.

```bash
docker-compose down -v
```

Step 2: Remove the `tfe.local` certificate from keychain

Step 3: Remove the `tfe.local` hostname from `/etc/hosts`

# 6. Misc

## 6.1 Useful docker compose commands

Access PostgreSQL

```bash
docker exec -it tfe-postgres psql -U tfeadmin -d tfe
```

Access Redis. Replace `<REDIS_PASSWORD>` with the password from the `.env` file.

```bash
docker exec -it tfe-redis redis-cli -a <REDIS_PASSWORD>
```

Check that all containers are running:

```bash
docker-compose ps
```

View logs:

```bash
docker-compose logs -f
docker-compose logs -f tfe
docker-compose logs -f postgres
docker-compose logs -f redis
```

## 6.2 Error if self-signed cert is not added to keychain

If the certificate is not added to the keystore, running `terraform init` results in the following error

> Error: Failed to request discovery document: Get "https://tfe.local/.well-known/terraform.json": tls: failed to verify certificate: x509: certificate signed by unknown authority

![failed to verify cert](./docs/04-misc/01-cert-error/01-failed-to-verify-cert.png)
