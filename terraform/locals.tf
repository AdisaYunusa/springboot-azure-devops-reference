locals {
  # Naming convention:
  # <organisation>-<workload>-<environment>-<region-code>-<resource-type>
  name_prefix = lower(join("-", [
    var.organisation,
    var.workload,
    var.environment,
    var.region_code
  ]))

  compact_name_prefix = lower(join("", [
    var.organisation,
    var.workload,
    var.environment,
    var.region_code
  ]))

  names = {
    resource_group        = "${local.name_prefix}-rg"
    virtual_network       = "${local.name_prefix}-vnet"
    container_apps_subnet = "${local.name_prefix}-aca-snet"
    postgresql_subnet     = "${local.name_prefix}-pg-snet"
    private_dns_zone_link = "${local.name_prefix}-pg-dns-link"
    log_analytics         = "${local.name_prefix}-law"
    container_environment = "${local.name_prefix}-cae"
    # Container App names are limited to 32 characters. Trim the readable
    # prefix while retaining the resource-type suffix.
    container_app    = "${trim(substr(local.name_prefix, 0, 29), "-")}-ca"
    managed_identity = "${local.name_prefix}-uai"

    # Globally unique names always retain the stable random suffix rather than
    # allowing a length truncation to remove the uniqueness component.
    postgresql_server = "${local.name_prefix}-pg-${random_string.name_suffix.result}"
    key_vault         = "${substr(local.compact_name_prefix, 0, 16)}kv${random_string.name_suffix.result}"
  }

  common_tags = merge(
    {
      application         = var.workload
      environment         = var.environment
      organisation        = var.organisation
      managed-by          = "terraform"
      owner               = var.owner
      repository          = var.repository
      cost-centre         = var.cost_centre
      data-classification = var.data_classification
    },
    var.additional_tags
  )

  postgresql_private_dns_zone_name = "private.postgres.database.azure.com"

  # Password version is deliberately visible in state so Terraform can detect
  # rotation requests, while the password value itself remains ephemeral.
  database_password_version = var.postgresql_password_version
}

resource "random_string" "name_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}
