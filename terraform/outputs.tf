output "resource_group_name" {
  description = "Name of the workload resource group."
  value       = azurerm_resource_group.main.name
}

output "container_app_name" {
  description = "Name of the Azure Container App."
  value       = azurerm_container_app.application.name
}

output "container_app_url" {
  description = "Public HTTPS endpoint of the application."
  value       = "https://${azurerm_container_app.application.ingress[0].fqdn}"
}

output "container_app_managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.container_app.id
}

output "container_app_managed_identity_principal_id" {
  description = "Principal ID used for Azure RBAC assignments."
  value       = azurerm_user_assigned_identity.container_app.principal_id
}

output "postgresql_server_name" {
  description = "Name of the private PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgresql_server_fqdn" {
  description = "Private PostgreSQL server FQDN."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_database_name" {
  description = "Application database name."
  value       = azurerm_postgresql_flexible_server_database.application.name
}

output "key_vault_name" {
  description = "Key Vault that stores application database credentials."
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the application Key Vault."
  value       = azurerm_key_vault.main.vault_uri
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.main.id
}

output "deployed_container_image" {
  description = "Immutable container image reference deployed by the Container App."
  value       = var.container_image
}
