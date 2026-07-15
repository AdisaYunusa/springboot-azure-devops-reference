# Mock every provider so these tests evaluate the bootstrap configuration
# without authenticating to Azure, creating resources, or waiting 30 seconds.
mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      object_id       = "22222222-2222-2222-2222-222222222222"
      subscription_id = "33333333-3333-3333-3333-333333333333"
    }
  }

  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/hmcts-tfstate-uks-rg"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/hmcts-tfstate-uks-rg/providers/Microsoft.Storage/storageAccounts/hmctstfstateuksa1b2c3d4"
    }
  }

  mock_resource "azurerm_storage_container" {
    defaults = {
      id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/hmcts-tfstate-uks-rg/providers/Microsoft.Storage/storageAccounts/hmctstfstateuksa1b2c3d4/blobServices/default/containers/tfstate"
    }
  }
}

mock_provider "random" {
  override_during = plan

  mock_resource "random_string" {
    defaults = {
      result = "a1b2c3d4"
    }
  }
}

mock_provider "time" {
  override_during = plan
}

variables {
  subscription_id = "33333333-3333-3333-3333-333333333333"
  owner           = "platform-engineering"
  repository      = "github.com/hmcts/hmcts-dev-test-backend"

  backend_allowed_ip_cidrs = [
    "203.0.113.10/32",
  ]

  additional_tags = {
    environment = "shared"
    cost-centre = "technical-assessment"
  }
}

run "bootstrap_naming_and_tags" {
  command = plan

  assert {
    condition     = local.prefix == "hmcts-tfstate-uks"
    error_message = "The bootstrap naming prefix must combine organisation, tfstate, and region code in lowercase."
  }

  assert {
    condition     = random_string.suffix.length == 8
    error_message = "The storage-account suffix must contain eight characters."
  }

  assert {
    condition     = random_string.suffix.upper == false && random_string.suffix.lower == true && random_string.suffix.numeric == true && random_string.suffix.special == false
    error_message = "The random suffix must contain only lowercase letters and numbers."
  }

  assert {
    condition     = azurerm_resource_group.state.name == "hmcts-tfstate-uks-rg"
    error_message = "The state resource group name does not follow the expected naming convention."
  }

  assert {
    condition     = azurerm_resource_group.state.location == "uksouth"
    error_message = "The bootstrap should use UK South by default."
  }

  assert {
    condition = azurerm_resource_group.state.tags == {
      application = "terraform-state"
      managed-by  = "terraform-bootstrap"
      owner       = "platform-engineering"
      repository  = "github.com/hmcts/hmcts-dev-test-backend"
      environment = "shared"
      cost-centre = "technical-assessment"
    }
    error_message = "The resource group must receive the merged governance tags."
  }

  assert {
    condition     = azurerm_storage_account.state.name == "hmctstfstateuksa1b2c3d4"
    error_message = "The storage-account name must use the normalised prefix and deterministic eight-character suffix."
  }

  assert {
    condition     = length(azurerm_storage_account.state.name) <= 24
    error_message = "The generated Azure Storage account name must not exceed 24 characters."
  }
}

run "storage_security_and_recovery_baseline" {
  command = plan

  assert {
    condition     = azurerm_storage_account.state.account_kind == "StorageV2"
    error_message = "Terraform state must use a StorageV2 account."
  }

  assert {
    condition     = azurerm_storage_account.state.account_tier == "Standard" && azurerm_storage_account.state.account_replication_type == "ZRS"
    error_message = "Terraform state storage must use Standard ZRS replication."
  }

  assert {
    condition     = azurerm_storage_account.state.min_tls_version == "TLS1_2"
    error_message = "Terraform state storage must enforce TLS 1.2 or later."
  }

  assert {
    condition     = azurerm_storage_account.state.https_traffic_only_enabled == true
    error_message = "Terraform state storage must accept HTTPS traffic only."
  }

  assert {
    condition     = azurerm_storage_account.state.shared_access_key_enabled == false
    error_message = "Shared-key authentication must remain disabled so the backend uses Microsoft Entra ID."
  }

  assert {
    condition     = azurerm_storage_account.state.allow_nested_items_to_be_public == false
    error_message = "Anonymous public access to nested storage items must remain disabled."
  }

  assert {
    condition     = azurerm_storage_account.state.infrastructure_encryption_enabled == true
    error_message = "Infrastructure-level encryption must remain enabled for the state account."
  }

  assert {
    condition     = azurerm_storage_account.state.network_rules[0].default_action == "Deny"
    error_message = "Storage network rules must deny traffic by default."
  }

  assert {
    condition     = contains(azurerm_storage_account.state.network_rules[0].bypass, "AzureServices")
    error_message = "Trusted Azure services must be present in the configured network-rule bypass list."
  }

  assert {
    condition     = contains(azurerm_storage_account.state.network_rules[0].ip_rules, "203.0.113.10/32")
    error_message = "The configured backend administrator CIDR must be applied to the storage firewall."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].versioning_enabled == true
    error_message = "Blob versioning must remain enabled to support Terraform state recovery."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days == 30
    error_message = "Blob soft-delete retention must use the configured 30-day default."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days == 30
    error_message = "Container soft-delete retention must use the configured 30-day default."
  }
}

run "rbac_and_private_state_container" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.terraform_state_contributor.scope == azurerm_storage_account.state.id
    error_message = "Storage Blob Data Contributor must be scoped to the Terraform state storage account."
  }

  assert {
    condition     = azurerm_role_assignment.terraform_state_contributor.role_definition_name == "Storage Blob Data Contributor"
    error_message = "The execution identity must receive Storage Blob Data Contributor for state operations."
  }

  assert {
    condition     = azurerm_role_assignment.terraform_state_contributor.principal_id == "22222222-2222-2222-2222-222222222222"
    error_message = "The role assignment must target the identity executing the bootstrap."
  }

  assert {
    condition     = time_sleep.wait_for_storage_rbac.create_duration == "30s"
    error_message = "The bootstrap must retain the RBAC propagation delay before creating the container."
  }

  assert {
    condition     = azurerm_storage_container.state.name == "tfstate"
    error_message = "The default Terraform state container name must be tfstate."
  }

  assert {
    condition     = azurerm_storage_container.state.storage_account_id == azurerm_storage_account.state.id
    error_message = "The state container must be created in the dedicated Terraform state storage account."
  }

  assert {
    condition     = azurerm_storage_container.state.container_access_type == "private"
    error_message = "The Terraform state container must remain private."
  }
}

run "backend_outputs_are_usable" {
  command = plan

  assert {
    condition     = output.backend_resource_group_name == "hmcts-tfstate-uks-rg"
    error_message = "The backend resource-group output must match the created resource group."
  }

  assert {
    condition     = output.backend_storage_account_name == "hmctstfstateuksa1b2c3d4"
    error_message = "The backend storage-account output must match the created storage account."
  }

  assert {
    condition     = output.backend_container_name == "tfstate"
    error_message = "The backend container output must match the created state container."
  }

  assert {
    condition     = strcontains(output.backend_hcl, "resource_group_name  = \"hmcts-tfstate-uks-rg\"")
    error_message = "The generated backend HCL must contain the state resource-group name."
  }

  assert {
    condition     = strcontains(output.backend_hcl, "storage_account_name = \"hmctstfstateuksa1b2c3d4\"")
    error_message = "The generated backend HCL must contain the state storage-account name."
  }

  assert {
    condition     = strcontains(output.backend_hcl, "container_name       = \"tfstate\"")
    error_message = "The generated backend HCL must contain the state container name."
  }

  assert {
    condition     = strcontains(output.backend_hcl, "key                  = \"hmcts-devtest/dev.tfstate\"")
    error_message = "The generated backend HCL must contain the development state key."
  }

  assert {
    condition     = strcontains(output.backend_hcl, "use_azuread_auth     = true")
    error_message = "The generated backend HCL must enable Microsoft Entra authentication."
  }
}

run "rejects_invalid_state_retention" {
  command = plan

  variables {
    state_delete_retention_days = 6
  }

  expect_failures = [
    var.state_delete_retention_days,
  ]
}

run "rejects_invalid_backend_cidr" {
  command = plan

  variables {
    backend_allowed_ip_cidrs = [
      "not-a-cidr",
    ]
  }

  expect_failures = [
    var.backend_allowed_ip_cidrs,
  ]
}
