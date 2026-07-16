# Azure infrastructure — Task 3

This Terraform configuration deploys the containerised Spring Boot application
to Azure Container Apps with a private Azure Database for PostgreSQL Flexible
Server, Azure Key Vault-backed credentials, managed identity, private
networking, health probes, autoscaling, Log Analytics and remote state.

It intentionally meets the assessment's minimum requirements and adds
production-oriented controls without introducing unnecessary AKS, service-mesh
or multi-registry complexity.

## Architecture

```text
Internet
   |
   | HTTPS only
   v
Azure Container App
   |-- immutable GHCR image (Git SHA or digest)
   |-- user-assigned managed identity
   |-- startup, process-level TCP liveness and database-aware readiness probes
   |-- HTTP autoscaling
   |
   +---- Key Vault secret references
   |        |-- PostgreSQL username
   |        `-- PostgreSQL password
   |
   `---- private VNet connection
             |
             `-- PostgreSQL Flexible Server
                   |-- delegated subnet
                   |-- private DNS
                   |-- public access disabled
                   `-- TLS required

Container Apps application and platform logs are retained in Log Analytics.
Terraform state is stored separately in a hardened Azure Storage backend.
```

## Resource naming

Resources follow:

```text
<organisation>-<workload>-<environment>-<region-code>-<resource-type>
```

Examples:

```text
hmcts-devtest-dev-uks-rg
hmcts-devtest-dev-uks-vnet
hmcts-devtest-dev-uks-ca
hmcts-devtest-dev-uks-pg-<stable-random-suffix>
```

Globally unique services such as Key Vault and PostgreSQL receive a stable
six-character suffix generated once and retained in Terraform state. Name
construction reserves space for that suffix so length truncation can never
remove the uniqueness component.

## Mandatory governance tags

Every Azure resource that supports tags receives:

- `application`
- `environment`
- `organisation`
- `managed-by`
- `owner`
- `repository`
- `cost-centre`
- `data-classification`

`additional_tags` can add organisation-specific metadata.

## Security design

### Private PostgreSQL

PostgreSQL is deployed into a dedicated delegated subnet with:

```hcl
public_network_access_enabled = false
```

A private DNS zone linked to the VNet lets the Container App resolve the
database FQDN. No `0.0.0.0/0` firewall rule or "allow all Azure services"
database shortcut is used.

### Key Vault and managed identity

The Container App uses a user-assigned managed identity and receives only the
`Key Vault Secrets User` role on the application vault. Database values are
injected as Key Vault-backed Container App secret references rather than
plaintext environment values.

The Key Vault:

- uses Azure RBAC;
- has purge protection and 90-day soft-delete retention;
- defaults network access to deny;
- allows the Container Apps subnet;
- allows only explicitly supplied deployer public CIDRs;
- permits trusted Azure service bypass where required by the managed platform.

### Password never enters Terraform artifacts

Terraform 1.15 ephemeral resources and AzureRM write-only arguments are used:

```text
ephemeral random password
        |
        v
Key Vault value_wo
        |
        v
ephemeral Key Vault read
        |
        v
PostgreSQL administrator_password_wo
```

The password is generated, stored in Key Vault and applied to PostgreSQL
without being written to the Terraform plan or state. Only the integer
`postgresql_password_version` is stored. Increment that variable to rotate the
password deliberately.

### Immutable deployment

`container_image` accepts only:

```text
ghcr.io/...:sha-<full-40-character-Git-SHA>
```

or:

```text
ghcr.io/...@sha256:<64-character-image-digest>
```

Mutable tags such as `latest` are rejected by variable validation. This ties
Task 3 deployment directly to the image built, tested, scanned and published by
Task 2.

The example assumes the GHCR package is publicly readable. For a private
production registry, use Azure Container Registry with managed-identity
`AcrPull`, or store a narrowly scoped read-only GHCR token in Key Vault and add
a Container Apps registry secret. A long-lived registry token is intentionally
not embedded in this assessment code.

## Availability and cost profiles

The default `terraform.tfvars.example` is cost-conscious:

- one warm Container App replica;
- Consumption workload profile;
- PostgreSQL `B_Standard_B1ms`;
- 32 GiB auto-growing storage;
- seven-day backups;
- HA and geo-redundant backup disabled.

These controls are variables rather than hard-coded defaults so the
assessment can be tested economically while the production intent remains
clear.

## Monitoring

Log Analytics retains Container Apps console/platform logs and diagnostic logs
from Key Vault and PostgreSQL. It provides the evidence needed to troubleshoot:

- failed image pulls;
- application startup errors;
- Key Vault secret-resolution failures;
- private DNS or PostgreSQL connection failures;
- failing health probes;
- restarts and scaling behaviour.

Application Insights and alert rules are sensible future additions but are not
required to demonstrate the Task 3 infrastructure.

## Files

```text
terraform/
├── backend.tf
├── versions.tf
├── providers.tf
├── variables.tf
├── locals.tf
├── resource-group.tf
├── networking.tf
├── identity.tf
├── key-vault.tf
├── postgresql.tf
├── monitoring.tf
├── container-app.tf
├── checks.tf
├── outputs.tf
├── terraform.tfvars.example
├── backend.hcl.example
├── .tflint.hcl
├── bootstrap/
└── ci/
```

Files are split by responsibility for readability. Child modules are not used
because this is one small stack with one consumer; premature modules would add
interfaces and state complexity without meaningful reuse.

## Prerequisites

- Terraform 1.15.x
- Azure CLI
- an Azure subscription
- permission to create resource groups, networking, managed identities,
  PostgreSQL, Key Vault and role assignments
- a successfully published GHCR image from Task 2
- your public IP when applying from a public workstation

Authenticate locally:

```bash
az login
az account set --subscription "<subscription-id>"
```

AzureRM v4 also requires the subscription ID in `terraform.tfvars` or
`ARM_SUBSCRIPTION_ID`.

## State bootstrap

Create the backend first:

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw backend_hcl
```

Copy the output into `terraform/backend.hcl`.

The main stack uses partial backend configuration so credentials and
environment-specific state names are not hard-coded:

```bash
cd ..
terraform init -backend-config=backend.hcl
```

The Azure Storage backend provides central state, locking and controlled
access. The bootstrap account enables versioning, soft delete, TLS 1.2,
infrastructure encryption, a deny-by-default network firewall and Entra/RBAC
authentication.

## Configure a development deployment

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
```

Replace:

- `subscription_id`;
- `owner`;
- `repository`;
- `container_image`;
- `key_vault_deployer_ip_cidrs`;
- backend storage details.

Find your public IP and express it as `/32`. Do not commit either local file.

## Local quality checks

```bash
terraform fmt -check -recursive -diff
terraform init -backend=false
terraform validate
terraform test
tflint --init
tflint --recursive
trivy config .
```

The native Terraform tests use mocked providers and do not deploy Azure
resources. They assert the private database, Key Vault protections, HTTPS-only
ingress, managed identity, replica baseline and production resilience
overrides.

## Plan and apply

After local validation:

```bash
terraform init -backend-config=backend.hcl -reconfigure
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Do not commit the binary plan file. A saved plan can contain sensitive
infrastructure data even though the generated database password is excluded by
the write-only design.

Retrieve useful values:

```bash
terraform output
terraform output -raw container_app_url
```

No output exposes the database password.

## Password rotation

Increment:

```hcl
postgresql_password_version = 2
```

Terraform generates a new ephemeral password, writes a new Key Vault value and
updates PostgreSQL through the matching write-only version. The Container App
uses a versionless Key Vault reference so it can consume the current secret.

Schedule rotation during a controlled change window and verify how the managed
Container Apps revision refreshes the secret reference in the target
environment. For strict immediate rotation, create a new revision after the
secret update.

## CI integration

Copy `ci/terraform-checks-job.yml` into `.github/workflows/ci.yml`, then follow
`ci/ci-gate-update.md`.

The job runs:

```text
terraform fmt
terraform init -backend=false
terraform validate
terraform test
TFLint
```

The existing Trivy filesystem misconfiguration job already scans Terraform, so
a second duplicate Trivy job is unnecessary.

Static PR checks require no Azure credentials. A later authenticated plan
workflow should use GitHub OIDC and a read-only/planning Azure identity. An
automatic `terraform apply` should not run on pull requests and should require a
protected GitHub environment approval.

## Destruction

For a disposable assessment environment:

```bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```

Key Vault purge protection intentionally means deletion is recoverable and
cannot be permanently purged immediately. The provider is configured not to
purge the vault during destroy.

Destroy the backend only after the workload state has been safely removed or
archived.

## Assumptions and trade-offs

- Azure Container Apps was chosen over AKS because the brief requires a
  container runtime, not a Kubernetes platform. Container Apps gives revisions,
  autoscaling, probes, managed identity and VNet integration with much less
  operational overhead.
- The application remains publicly reachable over HTTPS; PostgreSQL remains
  private.
- GHCR is retained to avoid duplicating the Task 2 release pipeline with ACR.
- HA and geo-redundant backups are demonstrated but disabled in the
  cost-conscious example.
- Key Vault and the state storage account retain public endpoints behind
  deny-by-default firewalls so explicitly allow-listed deployment agents have a
  route. A mature private platform can use private endpoints and self-hosted
  runners in the VNet.
- Terraform creates the current operator's Key Vault data-plane role so the
  stack is self-contained. In a centralised organisation, platform
  administrators would pre-provision this permission instead.
