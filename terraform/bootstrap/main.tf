locals {
  prefix = lower("${var.organisation}-tfstate-${var.region_code}")

  tags = merge(
    {
      application = "terraform-state"
      managed-by  = "terraform-bootstrap"
      owner       = var.owner
      repository  = var.repository
    },
    var.additional_tags
  )
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "${local.prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "state" {
  name                = "${substr(replace("${var.organisation}tfstate${var.region_code}", "-", ""), 0, 16)}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_replication_type = "ZRS"
  account_kind             = "StorageV2"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  public_network_access_enabled     = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  infrastructure_encryption_enabled = true

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = var.backend_allowed_ip_rules
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.state_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.state_delete_retention_days
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "terraform_state_contributor" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_for_storage_rbac" {
  create_duration = "30s"

  depends_on = [
    azurerm_role_assignment.terraform_state_contributor,
  ]
}

resource "azurerm_storage_container" "state" {
  name                  = var.state_container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    time_sleep.wait_for_storage_rbac,
  ]
}
