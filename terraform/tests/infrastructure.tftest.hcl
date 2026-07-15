mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      object_id       = "22222222-2222-2222-2222-222222222222"
      subscription_id = "33333333-3333-3333-3333-333333333333"
    }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "a1b2c3"
    }
  }
}

mock_provider "time" {}

variables {
  subscription_id = "33333333-3333-3333-3333-333333333333"
  owner           = "platform-engineering"
  repository      = "github.com/example/springboot-azure-devops-reference"
  container_image = "ghcr.io/example/springboot-azure-devops-reference:sha-0123456789abcdef0123456789abcdef01234567"

  key_vault_deployer_ip_cidrs = [
    "203.0.113.10/32",
  ]
}

run "security_and_reliability_baseline" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server.main.public_network_access_enabled == false
    error_message = "PostgreSQL must not expose a public network endpoint."
  }

  assert {
    condition     = azurerm_key_vault.main.rbac_authorization_enabled == true
    error_message = "Key Vault must use Azure RBAC."
  }

  assert {
    condition     = azurerm_key_vault.main.purge_protection_enabled == true
    error_message = "Key Vault purge protection must remain enabled."
  }

  assert {
    condition     = azurerm_key_vault.main.network_acls[0].default_action == "Deny"
    error_message = "Key Vault network access must default to deny."
  }

  assert {
    condition     = azurerm_container_app.application.ingress[0].allow_insecure_connections == false
    error_message = "Container App ingress must reject insecure HTTP."
  }

  assert {
    condition     = azurerm_container_app.application.ingress[0].target_port == 4000
    error_message = "Container App ingress must route to the Spring Boot service on port 4000."
  }

  assert {
    condition     = azurerm_container_app.application.identity[0].type == "UserAssigned"
    error_message = "Container App must use a user-assigned managed identity."
  }

  assert {
    condition     = azurerm_container_app.application.template[0].min_replicas >= 1
    error_message = "At least one warm application replica must be maintained."
  }

  assert {
    condition     = azurerm_container_app.application.template[0].max_replicas >= azurerm_container_app.application.template[0].min_replicas
    error_message = "Maximum replicas cannot be lower than minimum replicas."
  }

  assert {
    condition     = azurerm_container_app_environment.main.zone_redundancy_enabled == false
    error_message = "The default development example should remain cost-conscious; production overrides this to true."
  }
}

run "production_overrides_enable_resilience" {
  command = plan

  variables {
    environment                             = "prod"
    container_min_replicas                  = 2
    container_max_replicas                  = 10
    container_app_zone_redundancy_enabled   = true
    postgresql_high_availability_enabled    = true
    postgresql_geo_redundant_backup_enabled = true
    postgresql_sku_name                     = "GP_Standard_D2s_v3"
    postgresql_storage_mb                   = 131072
    postgresql_backup_retention_days        = 35
    container_image                         = "ghcr.io/example/springboot-azure-devops-reference@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = azurerm_container_app_environment.main.zone_redundancy_enabled == true
    error_message = "Production Container Apps environment must support zone redundancy."
  }

  assert {
    condition     = length(azurerm_postgresql_flexible_server.main.high_availability) == 1
    error_message = "Production PostgreSQL must have a high-availability block."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.main.geo_redundant_backup_enabled == true
    error_message = "Production PostgreSQL must enable geo-redundant backups in this example."
  }

  assert {
    condition     = azurerm_container_app.application.template[0].min_replicas == 2
    error_message = "Production must maintain at least two warm replicas in this example."
  }
}
