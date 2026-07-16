provider "azurerm" {
  features {
    key_vault {
      # Production safety: deleting the Terraform resource does not
      # permanently purge a protected vault.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  # AzureRM v4 requires an explicit subscription context. Locally this can be
  # supplied through ARM_SUBSCRIPTION_ID; CI should use GitHub OIDC.
  subscription_id = var.subscription_id

  storage_use_azuread = true
}

data "azurerm_client_config" "current" {}
