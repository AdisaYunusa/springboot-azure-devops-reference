# Terraform backend bootstrap

This directory creates the Azure Storage resources required by the main
Terraform configuration's `azurerm` remote backend.

The backend cannot create itself because Terraform must initialise its backend
before it can manage normal resources. The bootstrap configuration therefore
uses local state for its one-time creation.

## Create the backend

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
az login
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw backend_hcl
```

Copy the generated values into `../backend.hcl`, or automate the file creation using "terraform output -raw backend_hcl > ../backend.hcl" then initialise the main stack:

```bash
cd ..
terraform init -backend-config=backend.hcl -reconfigure
```

## Security decisions

- State blobs use Microsoft Entra ID/RBAC rather than storage-account keys.
- The bootstrap waits for the data-plane role assignment to propagate before
  creating the private state container.
- Public anonymous blob access and shared-key authentication are disabled.
- TLS 1.2, infrastructure encryption, versioning, blob soft delete and
  container soft delete are enabled.
- The storage endpoint remains publicly addressable but its firewall defaults to
  deny and permits only explicitly supplied IPs; Microsoft Entra
  authentication is still required.
- A mature enterprise implementation can replace public CIDR rules with a
  private endpoint and a self-hosted runner or fixed private deployment agent.

Protect the bootstrap local state because it remains the source of truth for
the backend infrastructure. It does not contain the application database
password, but it still contains infrastructure metadata and role assignments.
