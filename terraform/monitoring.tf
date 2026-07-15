resource "azurerm_log_analytics_workspace" "main" {
  name                = local.names.log_analytics
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.common_tags
}

resource "azurerm_container_app_environment" "main" {
  name                           = local.names.container_environment
  location                       = azurerm_resource_group.main.location
  resource_group_name            = azurerm_resource_group.main.name
  infrastructure_subnet_id       = azurerm_subnet.container_apps.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  zone_redundancy_enabled        = var.container_app_zone_redundancy_enabled

  # Explicitly creating a workload-profile environment preserves the option to
  # add dedicated profiles later without replacing the environment.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.common_tags
}


resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "send-to-${local.names.log_analytics}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "send-to-${local.names.log_analytics}"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
