# HMCTS Dev Test Backend — DTS DevOps Technical Test

This repository contains my implementation of the DTS DevOps technical test. The solution takes the supplied Java 21 Spring Boot application through four delivery concerns:

1. containerising the application and PostgreSQL for repeatable local execution;
2. implementing a secure, gated GitHub Actions CI/CD workflow;
3. defining production-minded Azure infrastructure using Terraform; and
4. documenting how the solution works, the decisions made and the improvements I would make for a production service.

The implementation deliberately goes beyond the minimum requirements where doing so improves security, traceability or operability, while avoiding unnecessary platform complexity for a single backend service.

## Solution summary

| Area | Implementation |
|---|---|
| Application | Java 21 Spring Boot service on port `4000` |
| Local runtime | Docker Compose with PostgreSQL 16 |
| Container | Multi-stage Java build, minimal JRE runtime, non-root user and health check |
| CI/CD | GitHub Actions with tests, Checkstyle, Trivy, Terraform checks, container testing and GHCR publication |
| Image traceability | Immutable full Git SHA tag; `master` and `latest` aliases published only from `master` |
| Infrastructure | Azure Container Apps, PostgreSQL Flexible Server, Key Vault, managed identity, private networking and Log Analytics |
| Terraform state | Separate hardened Azure Storage bootstrap using Microsoft Entra ID and Azure RBAC |
| Secret handling | Terraform ephemeral resources and write-only provider arguments keep the generated database password out of plans and state |
| Deployment scope | Terraform `plan` and `apply` are intentionally not automated because the assessment does not require an Azure deployment |

## High-level architecture

### Local development

```text
Developer
   |
   | http://localhost:4000
   v
Docker Compose
   |
   +-- Spring Boot application
   |     |-- Java 21
   |     |-- non-root UID 10001
   |     `-- health/readiness endpoints
   |
   `-- PostgreSQL 16
         `-- persistent named volume
```

### Target Azure architecture

```text
Internet
   |
   | HTTPS only
   v
Azure Container App
   |-- immutable GHCR image
   |-- user-assigned managed identity
   |-- startup, liveness and readiness probes
   |-- HTTP concurrency autoscaling
   |
   +-- Key Vault secret references
   |      |-- PostgreSQL administrator username
   |      `-- PostgreSQL administrator password
   |
   `-- VNet-integrated Container Apps environment
          |
          `-- Azure Database for PostgreSQL Flexible Server
                 |-- dedicated delegated subnet
                 |-- private DNS
                 |-- public access disabled
                 `-- TLS required

Application and platform logs
   |
   `-- Log Analytics workspace

Terraform
   |
   `-- Azure Storage remote backend
          |-- private blob container
          |-- Entra ID/RBAC authentication
          |-- blob versioning and soft delete
          `-- deletion protection
```

## Repository structure

```text
.
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── codeql.yml
├── src/
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .env.example
├── build.gradle
├── gradlew
├── terraform/
│   ├── backend.tf
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── checks.tf
│   ├── networking.tf
│   ├── identity.tf
│   ├── key-vault.tf
│   ├── postgresql.tf
│   ├── container-app.tf
│   ├── monitoring.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── backend.hcl.example
│   ├── .tflint.hcl
│   ├── README.md
│   └── bootstrap/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       ├── README.md
│       └── tests/
│           └── bootstrap.tftest.hcl
└── README.md
```

The root README is the entry point for the complete assessment. More detailed Terraform operating guidance is kept in `terraform/README.md`, while the privileged remote-state setup is documented separately in `terraform/bootstrap/README.md`.

# Task 1 — Database Wiring, Containerisation and local execution

## Application database integration

1. To enable PostgreSQL connectivity, I uncommented and configured the datasource section in application.yaml and added the required dependencies to build.gradle:
    - implementation 'org.springframework.boot:spring-boot-starter-jdbc'
    - runtimeOnly 'org.postgresql:postgresql'
2. Spring JDBC was selected instead of JPA because the assessment only requires database connectivity, not an ORM layer.
3. The datasource uses environment variables for the host, port, database name, username and password, allowing the same application image to run securely across local, CI and Azure environments.
4. Database connectivity is also included in the readiness health check, so /health/readiness confirms that the application can successfully connect to PostgreSQL.

## Container design

The application uses a multi-stage Docker build:

1. a Java 21 JDK stage compiles and packages the Spring Boot application;
2. only the resulting executable JAR is copied into a Java 21 JRE runtime image;
3. the application runs as a dedicated non-root user with UID/GID `10001`;
4. port `4000` is exposed;
5. the container health check calls the application health endpoint;
6. the entry point uses exec form so Unix signals are delivered correctly to the Java process.

This approach separates build tooling from the runtime image, reduces the final attack surface and avoids running the service as root.

The application database configuration is supplied through environment variables:

```text
DB_HOST
DB_PORT
DB_NAME
DB_USER_NAME
DB_PASSWORD
DB_OPTIONS
```

Spring Boot readiness includes the database health contributor, so `/health/readiness` confirms more than process availability: it verifies that the service can reach PostgreSQL.

## Docker Compose design

`docker-compose.yml` defines:

- the application image;
- PostgreSQL 16;
- service health checks;
- startup ordering based on database health;
- a dedicated network;
- a named PostgreSQL volume;
- host-loopback port binding;
- a read-only application filesystem;
- temporary writable filesystems where required;
- dropped Linux capabilities; and
- `no-new-privileges`.

The application port and PostgreSQL port are bound to `127.0.0.1` rather than all host interfaces. This makes the local environment available to the developer without exposing it to the wider network.

## Prerequisites

- Docker Desktop or Docker Engine with Docker Compose v2, for building and running the application and PostgreSQL containers.
- Git, for cloning the repository, creating branches and managing source-control changes. When working from a fork, clone the forked repository rather than the original        repository.
- A command-line environment, such as PowerShell, Windows Command Prompt, Git Bash, WSL, Linux/macOS terminal or the integrated terminal provided by an IDE or code editor.
- An IDE or code editor, such as Visual Studio Code, IntelliJ IDEA or Eclipse, for reviewing and modifying the application, Docker, workflow and Terraform files. This is optional if the repository is only being run rather than changed.
- An HTTP client, such as curl, Postman or a web browser, for testing the exposed application and health endpoints.
- Java 21 only when running Gradle tasks directly outside Docker
- Terraform and TFLint, only when running the infrastructure validation commands locally. Their versions should match those defined in the GitHub Actions workflow and Terraform configuration.

## Run locally

Create the local environment file:

```bash
cp .env.example .env
```

Set a non-default local PostgreSQL password in `.env`. The file is ignored by Git and must not be committed.

Build and start the services:

```bash
docker compose up --build --detach
```

Check service status:

```bash
docker compose ps
```

Follow logs:

```bash
docker compose logs --follow app db
```

Verify the application:

```bash
curl --fail http://localhost:4000/
curl --fail http://localhost:4000/get-example-case
curl --fail http://localhost:4000/health
curl --fail http://localhost:4000/health/readiness
```

Stop the environment while retaining PostgreSQL data:

```bash
docker compose down
```

Remove the environment and its local database volume:

```bash
docker compose down --volumes
```

## Run application tests locally

```bash
./gradlew clean test integration --no-daemon
```

With the Compose environment running, the functional and smoke suites can target the real container:

```bash
TEST_URL=http://localhost:4000 \
SERVER_PORT=0 \
DB_HOST=127.0.0.1 \
DB_PORT=5432 \
DB_NAME=devtest \
DB_USER_NAME=postgres \
DB_PASSWORD="<local-password>" \
./gradlew functional smoke --no-daemon
```

`SERVER_PORT=0` prevents the test Spring context from competing with the Compose application for port `4000`.

# Task 2 — CI/CD

The main workflow is defined in `.github/workflows/ci.yml`.

## Triggers and concurrency

The workflow runs on pushes to any branch, pull requests targeting `master`, and manual execution. Concurrency cancels an older run when a newer commit is pushed to the same branch or pull request.

The workflow uses least-privilege permissions by default. Jobs request additional permissions only when required for operations such as test annotations, SARIF upload, package publication or attestations.

## Pipeline stages

### 1. Build and test

The application job configures Java 21, uses the Gradle dependency cache, runs unit and integration tests, creates JaCoCo coverage reports, publishes JUnit annotations where permissions allow, and uploads reports as workflow artefacts.

### 2. Static analysis

Checkstyle runs independently across the application and configured test source sets. Keeping this separate provides clearer feedback: a style failure is not hidden behind a test failure.

### 3. Source security

Trivy scans the checked-out repository before the container is built:

- committed secrets are blocking;
- HIGH and CRITICAL Dockerfile/IaC misconfigurations are blocking.

Repository scanning is required because the Dockerfile, Compose configuration and Terraform source are not present in the final runtime image.

### 4. Terraform checks

The Terraform job performs non-destructive validation only and requires no Azure credentials.

It:

- checks formatting recursively;
- initialises and validates the bootstrap root with the backend disabled;
- runs bootstrap native tests with mocked providers;
- initialises and validates the main Terraform root with the backend disabled;
- initialises the shared AzureRM TFLint plugin using the workflow token;
- lints the bootstrap and main Terraform roots independently; and
- relies on the repository Trivy scan for IaC security findings.

The two Terraform directories are separate root modules and are therefore initialised and validated independently.

Native Terraform tests are retained for the backend bootstrap because mocked providers can verify naming, tagging, storage security, recovery controls, RBAC, private container access, backend outputs and validation rules without creating Azure resources.

Native mocked tests are intentionally not run against the main root. Its PostgreSQL credential workflow uses provider-backed ephemeral resources and write-only arguments so the password is not persisted in Terraform state or plan files. Terraform provider mocks do not currently support ephemeral resource types. I chose to preserve the stronger secret-handling design rather than replace it with state-persisted credentials purely to make a mock test pass. The main root remains gated by formatting, `terraform validate`, TFLint, defensive variable/check logic and Trivy.

### 5. Build the image once

The container is built once with Docker Buildx after the initial quality and source-security gates succeed.

The image receives a full immutable Git SHA tag and OCI source, revision and creation labels. The exact image is exported as a compressed workflow artefact with a SHA-256 checksum. Downstream jobs download and verify this same image rather than rebuilding it, avoiding the risk of scanning one image and publishing a different one.

### 6. Container security

The exact image is scanned using Trivy:

- HIGH vulnerabilities are reported;
- CRITICAL vulnerabilities block the workflow;
- embedded secrets block the workflow;
- vulnerability findings are generated as SARIF and retained as a workflow artefact.

### 7. Functional and smoke testing

The pipeline loads the exact built image and starts it with PostgreSQL using Docker Compose.

It verifies the application and database become healthy, the endpoints respond, database-aware readiness succeeds, the container runs as UID `10001`, and the repository’s functional and smoke suites pass against the running service.

The CI database password is created only for that workflow execution and is not a long-lived repository secret.

### 8. CI gate

A final aggregate gate evaluates all required jobs. This provides branch protection with one stable status check rather than coupling repository rules to every internal job.

It evaluates the outcome of the required pipeline stages, including:

    - application build, unit tests and integration tests;
    - Checkstyle static analysis;
    - source, secret and IaC security scanning;
    - Terraform formatting, validation, tests and TFLint;
    - container image build;
    - container vulnerability and secret scanning; and
    - functional and smoke testing against the built container.

The workflow is designed to fail when any required stage does not pass because each stage validates a different aspect of the same release candidate. Allowing the pipeline to continue after a failed test, security scan or infrastructure check could result in an unverified, vulnerable or incorrectly configured image being published.

The gate therefore passes only when every required job completes successfully. If any required stage fails, is cancelled or does not complete successfully, the gate fails and the publishing job is prevented from running.

CodeQL remains an independent defence-in-depth workflow and is not included in the primary CI gate.

### 9. Publish

Publishing is restricted to successful pushes to `master`.

The image is published to GitHub Container Registry with:

```text
sha-<full-commit-sha>
master
latest
```

The SHA tag provides permanent source-to-image traceability. `master` and `latest` are convenience aliases and move only when a new `master` build succeeds.

Semantic Versioning tags such as 1.2.0 were intentionally not used because the assessment does not define:
    - a formal release process, an application version source, release approval rules, changelog generation or criteria for deciding whether a change is major, minor or patch.

Automatically creating a Semantic Version for every successful merge would therefore produce arbitrary or misleading release numbers. Commit SHA tagging is more accurate for a continuous-integration assessment because every image maps directly to the exact source revision that produced it.

Semantic Versioning would be appropriate when the service has a formal release lifecycle, for example:
    - releases are explicitly approved and tagged;
    - breaking, feature and corrective changes are classified;
    - changelogs and release notes are generated;
    - environments promote a named release rather than an arbitrary commit; or
    - multiple supported application versions must be identified.

In that model, a release tag such as v1.3.0 could publish both:

1.3.0
sha-<full-commit-sha>

The Semantic Version would provide a human-readable release identity, while the SHA tag would retain immutable technical traceability.

The publication stage also produces an SBOM and build-provenance attestations. These can appear in GHCR as additional untagged OCI objects associated with the image; they are supply-chain metadata rather than duplicate application releases.

## CodeQL

The inherited CodeQL workflow is retained as an independent defence-in-depth source-security control.

Only minimal project-alignment changes were made:

- Java 21 is configured;
- Ubuntu 24.04 is used; and
- `./gradlew clean classes` is run so CodeQL observes the project’s real compilation.

CodeQL remains separate from the primary CI gate. It may report that overlay analysis is unavailable and fall back to a normal full database because no explicit overlay-compatible build mode is configured. The Java analysis still completes successfully, so I did not introduce further workflow changes solely to remove that informational warning.

# Task 3 — Terraform infrastructure

The Terraform configuration targets Azure because the role and assessment context are Azure-focused.

## Platform choice

Azure Container Apps was selected instead of AKS or a dedicated App Service environment.

For one stateless backend service, Container Apps provides managed container execution, HTTPS ingress, revisions, health probes, autoscaling, managed identity and VNet integration without the operational overhead of a Kubernetes control plane, node pools, cluster upgrades and cluster-level add-ons.

AKS would become appropriate if the service estate grew to require shared Kubernetes APIs, custom operators, complex scheduling or a broader internal platform.

## Main resources

The Terraform root creates:

- resource group;
- virtual network;
- dedicated Container Apps and PostgreSQL subnets;
- private DNS for PostgreSQL;
- user-assigned managed identity;
- Azure Key Vault;
- PostgreSQL administrator username and generated password secrets;
- Azure Database for PostgreSQL Flexible Server;
- application database;
- Log Analytics workspace;
- Azure Container Apps environment; and
- Azure Container App.

Resources follow:

```text
<organisation>-<workload>-<environment>-<region-code>-<resource-type>
```

Globally unique names receive a stable random suffix retained in state. Governance tags identify the application, environment, owner, repository, cost centre, data classification and Terraform ownership.

## Network and database security

PostgreSQL is deployed in a dedicated delegated subnet, has public network access disabled, uses VNet-linked private DNS, requires TLS, and has configurable backup, storage, maintenance and availability settings. Persistent database resources are protected from accidental Terraform deletion.

The Container App reaches PostgreSQL through the private VNet path. No public PostgreSQL firewall or broad “allow Azure services” database shortcut is used.

## Key Vault and identity

The Container App uses a user-assigned managed identity with the least-privilege `Key Vault Secrets User` role.

The deployment identity receives the permissions required to create or update database credentials. The identity executing Terraform must already have sufficient Azure RBAC authority to create the required role assignments. Terraform does not grant itself privileges; Azure evaluates the permissions of the authenticated user, service principal or managed identity.

The submitted Key Vault design uses Azure RBAC, purge protection, soft-delete retention, default-deny network rules, access from the Container Apps subnet and one approved static public egress IP for the Terraform operator.

The variable remains a list so additional approved addresses can be supplied later, but the assessment assumes one controlled egress IP for simplicity and minimum exposure.

In a mature Azure landing zone, the preferred design would use a Key Vault private endpoint with public network access disabled. Terraform would run from a corporate network or self-hosted runner connected through VPN or ExpressRoute. Where the gateway resides in a hub VNet, hub-and-spoke peering with gateway transit and private DNS resolution would also be required. Those shared platform dependencies are outside this self-contained assessment.

## Ephemeral database password

The PostgreSQL password workflow is:

```text
ephemeral random password
        |
        v
Key Vault write-only value
        |
        v
ephemeral Key Vault read
        |
        v
PostgreSQL write-only administrator password
```

The generated password is not persisted in Terraform state or saved plan files.

A separate integer version is stored:

```hcl
postgresql_password_version = 1
```

Normal Terraform operations do not deliberately rotate the password. Rotation is controlled by incrementing this version, which updates Key Vault and PostgreSQL during the same reviewed change.

## Immutable application image

Terraform accepts only:

```text
ghcr.io/...:sha-<40-character-Git-SHA>
```

or:

```text
ghcr.io/...@sha256:<64-character-digest>
```

Mutable-only references are rejected. This creates a direct link from the image built, tested and scanned in Task 2 to the revision proposed for Azure deployment.

The example assumes the GHCR package is publicly readable. A production implementation would preferably publish to Azure Container Registry and grant the Container App managed identity `AcrPull`.

## Monitoring

Log Analytics provides a foundation for investigating image pulls, startup failures, Key Vault reference failures, private DNS/database connectivity, health probes, restarts and scaling behaviour.

Application Insights, alerts, dashboards and service-level objectives are future operational enhancements rather than resources added solely to increase the apparent scope.

## Deletion protection

`lifecycle.prevent_destroy` protects remote-state and data-bearing application resources identified by TFLint, including the storage account/container, Key Vault/secrets and PostgreSQL resources.

This deliberately makes an ordinary `terraform destroy` fail. Controlled decommissioning would require a separate reviewed change after confirming backup, retention and approval requirements.

## Remote-state bootstrap

`terraform/bootstrap` is separate because the main state backend must exist before the main root can initialise against it.

The bootstrap creates:

- a dedicated resource group;
- a globally unique StorageV2 account;
- a private blob container;
- ZRS replication;
- HTTPS and TLS 1.2 enforcement;
- disabled shared-key authentication;
- Entra ID/RBAC access;
- deny-by-default network rules;
- blob versioning;
- blob/container soft-delete retention; and
- deletion protection.

The bootstrap grants its executing identity `Storage Blob Data Contributor` so Terraform can read, write and lease the state blob through Entra authentication.

Creating the role assignment requires an identity with elevated access-management permission such as an appropriately scoped RBAC administrator or Owner. In a controlled organisation, the bootstrap would normally be executed once by a platform team or an approved privileged workflow, not by normal application CI.

After bootstrap:

```bash
cd terraform/bootstrap
terraform output -raw backend_hcl > ../backend.hcl
```

The output command prints configuration; shell redirection creates or updates the file.

`backend.hcl` is environment-specific and ignored by Git. `backend.hcl.example` documents its shape without storing live credentials.

## Terraform local validation

Format the full Terraform tree:

```bash
terraform -chdir=terraform fmt -check -recursive -diff
```

Validate and test the bootstrap:

```bash
terraform -chdir=terraform/bootstrap init -backend=false -input=false
terraform -chdir=terraform/bootstrap validate -no-color
terraform -chdir=terraform/bootstrap test -no-color
```

Validate the main root:

```bash
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate -no-color
```

Initialise TFLint once and lint both roots:

```bash
tflint --chdir=terraform   --config="$(pwd)/terraform/.tflint.hcl"   --init

tflint --chdir=terraform/bootstrap   --config="$(pwd)/terraform/.tflint.hcl"   --format compact

tflint --chdir=terraform   --config="$(pwd)/terraform/.tflint.hcl"   --format compact
```

Scan the Terraform configuration:

```bash
trivy config terraform
```

# Assumptions and trade-offs

## No Azure deployment in the assessment

The repository defines the target infrastructure but does not run authenticated `terraform plan` or `terraform apply` in CI.

This is intentional because the assessment asks for infrastructure code rather than a live Azure deployment. Adding deployment would require subscription access, OIDC federation, environment-specific configuration, cost ownership and an approval model that are not supplied by the exercise.

## Cost-conscious defaults

`terraform.tfvars.example` represents a development/assessment profile: Container Apps Consumption, one warm replica, limited maximum replicas, burstable PostgreSQL, modest storage and backup retention, and disabled HA/geo-redundant backup.

Production values would be supplied through controlled environment configuration, with multiple replicas, zone redundancy, General Purpose PostgreSQL, high availability, longer retention and appropriate capacity. A second detailed production example was deliberately omitted to keep the submission focused and avoid presenting hypothetical configuration as an implemented deployment.

## Key Vault network access

The assessment uses one approved static public egress IP for Terraform data-plane access to the firewalled Key Vault. This is professional when the address belongs to a controlled VPN, NAT gateway or self-hosted runner. It is not the highest-maturity enterprise design; Private Link and private deployment connectivity are the preferred production evolution.

## State bootstrap lifecycle

Backend provisioning is a one-time privileged operation. It is separated from normal CI and should be manually initiated or run through an approved platform workflow.

Generation of `backend.hcl` can be automated after a successful bootstrap to reduce transcription errors, but backend creation should not run on every push or pull request.

## Main Terraform native testing limitation

The bootstrap is tested with native mocks. The main root is not, because its secure ephemeral resources are unsupported by provider mocks.

The future test would be an authenticated integration test in an isolated Azure test subscription using OIDC, temporary resources and guaranteed cleanup. Replacing ephemeral/write-only handling simply to permit mock tests would reduce security by persisting the password in state.

## No Kubernetes platform

AKS was not selected because the service does not justify the cost and operational burden of a dedicated Kubernetes platform. This is a proportionality decision, not a limitation in the Terraform approach.

# Future production improvements

## Change-aware CI/CD

A mature workflow would first detect changed paths and run only the relevant lane:

```text
Application-only change
  -> application build, tests, security, image build and testing
  -> publish only after successful merge to master

Terraform-only change
  -> Terraform formatting, validation, bootstrap tests, TFLint and IaC scanning
  -> no unnecessary Java compilation or image publication

Application and Terraform change
  -> run both lanes

Documentation-only change
  -> avoid expensive application and Terraform jobs

Workflow/shared CI change
  -> run the affected lane or both lanes
```

The workflow itself would still start so the required final status is always reported. Conditional jobs would be acceptable when skipped because they are not applicable, while failures in applicable jobs would block the gate.

Scheduled security scans would remain because newly disclosed vulnerabilities can affect unchanged dependencies and base images.

## Controlled Terraform delivery

The future lifecycle would be:

```text
Pull request
   |
   |-- fmt / validate / tests / lint / security
   `-- speculative plan for reviewer visibility
             |
             v
       approve and merge
             |
             v
fresh authoritative plan from the exact master commit
             |
             |-- save plan artefact
             |-- publish human-readable summary
             `-- protected production-environment approval
                         |
                         v
              apply the exact saved plan
```

The pull-request plan would support merge review. A fresh plan would still be generated after merge because the merge commit, state or Azure environment may have changed.

Production authentication would use GitHub OIDC rather than a client secret. The apply job would use a protected environment, required reviewers and concurrency with `cancel-in-progress: false`, so an active infrastructure change is never cancelled by a newer commit.

The privileged state bootstrap would remain a separate manually triggered workflow with narrower access and additional approval.

## Private platform connectivity

- Key Vault private endpoint with public access disabled
- storage-account private endpoint for remote state
- VPN or ExpressRoute connectivity
- hub-and-spoke gateway transit where applicable
- Azure DNS Private Resolver or equivalent forwarding
- privately connected self-hosted deployment runner

## Registry and supply chain

- Azure Container Registry
- managed-identity `AcrPull`
- formal semantic versioning and release tags
- signed images and deployment policy verification
- retained SBOM/provenance linked to release records

## Operability

- Application Insights/OpenTelemetry
- availability, latency and error-rate alerts
- PostgreSQL capacity and connection alerts
- dashboards and operational runbooks
- backup-restore testing
- documented SLOs and incident response
- scheduled Terraform drift detection that reports rather than automatically remediates changes

## Terraform structure

The current root is intentionally split into responsibility-based files rather than premature child modules. If multiple services or environments adopted the pattern, I would extract versioned modules for networking, Container Apps, PostgreSQL and observability, with automated module tests and release management.

# Assessment completion

| Task | Status | Evidence |
|---|---|---|
| Task 1 — Containerisation | Complete | `Dockerfile`, `docker-compose.yml`, `.env.example`, database and health configuration |
| Task 2 — CI/CD | Complete | `.github/workflows/ci.yml`, independent CodeQL workflow, GHCR publication |
| Task 3 — Terraform | Complete | `terraform/`, hardened state bootstrap and bootstrap native tests |
| Task 4 — Documentation | Complete | This README and the scoped Terraform READMEs |

The solution is designed to be reproducible locally, fail safely in CI, produce a traceable container artefact and demonstrate a secure, proportionate path to running the service on Azure.
