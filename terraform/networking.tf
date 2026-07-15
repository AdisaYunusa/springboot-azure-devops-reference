resource "azurerm_virtual_network" "main" {
  name                = local.names.virtual_network
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "container_apps" {
  name                 = local.names.container_apps_subnet
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.container_apps_subnet_cidr]

  # The service endpoint allows traffic originating from the delegated
  # Container Apps subnet to reach a network-restricted Key Vault.
  service_endpoints = ["Microsoft.KeyVault"]

  delegation {
    name = "container-apps-environment-delegation"

    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "postgresql" {
  name                 = local.names.postgresql_subnet
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.postgresql_subnet_cidr]

  delegation {
    name = "postgresql-flexible-server-delegation"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "postgresql" {
  name                = local.postgresql_private_dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                  = local.names.private_dns_zone_link
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.common_tags
}
