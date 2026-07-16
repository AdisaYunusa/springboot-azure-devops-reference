resource "azurerm_resource_group" "main" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.common_tags
}
