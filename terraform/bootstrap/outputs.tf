output "backend_resource_group_name" {
  description = "Resource group used by the azurerm backend."
  value       = azurerm_resource_group.state.name
}

output "backend_storage_account_name" {
  description = "Storage account used by the azurerm backend."
  value       = azurerm_storage_account.state.name
}

output "backend_container_name" {
  description = "Blob container used by the azurerm backend."
  value       = azurerm_storage_container.state.name
}

output "backend_hcl" {
  description = "Copy this block into ../backend.hcl and add an environment-specific key."
  value = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    key                  = "hmcts-devtest/dev.tfstate"
    use_azuread_auth     = true
  EOT
}
