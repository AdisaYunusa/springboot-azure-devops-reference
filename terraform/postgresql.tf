resource "azurerm_postgresql_flexible_server" "main" {
  name                          = local.names.postgresql_server
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = var.postgresql_version
  delegated_subnet_id           = azurerm_subnet.postgresql.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgresql.id
  public_network_access_enabled = false

  administrator_login               = var.postgresql_administrator_login
  administrator_password_wo         = ephemeral.azurerm_key_vault_secret.postgresql_password.value
  administrator_password_wo_version = local.database_password_version

  sku_name                     = var.postgresql_sku_name
  storage_mb                   = var.postgresql_storage_mb
  auto_grow_enabled            = true
  backup_retention_days        = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled = var.postgresql_geo_redundant_backup_enabled

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  dynamic "high_availability" {
    for_each = var.postgresql_high_availability_enabled ? [1] : []

    content {
      mode = "ZoneRedundant"
    }
  }

  maintenance_window {
    day_of_week  = var.postgresql_maintenance_day
    start_hour   = var.postgresql_maintenance_hour
    start_minute = 0
  }

  tags = local.common_tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgresql,
    azurerm_key_vault_secret.postgresql_password,
  ]

  lifecycle {
    # Azure may update the primary zone following an HA failover. Avoid forcing
    # Terraform to move the primary back solely to remove that service drift.
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone,
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "application" {
  name      = var.postgresql_database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "on"
}
