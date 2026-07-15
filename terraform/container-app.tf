resource "azurerm_container_app" "application" {
  name                         = local.names.container_app
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  max_inactive_revisions       = 5
  tags                         = local.common_tags

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.container_app.id,
    ]
  }

  secret {
    name                = "db-username"
    key_vault_secret_id = azurerm_key_vault_secret.postgresql_username.versionless_id
    identity            = azurerm_user_assigned_identity.container_app.id
  }

  secret {
    name                = "db-password"
    key_vault_secret_id = azurerm_key_vault_secret.postgresql_password.versionless_id
    identity            = azurerm_user_assigned_identity.container_app.id
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 4000
    transport                  = "auto"
    client_certificate_mode    = "ignore"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas                     = var.container_min_replicas
    max_replicas                     = var.container_max_replicas
    polling_interval_in_seconds      = 30
    cooldown_period_in_seconds       = 300
    termination_grace_period_seconds = 30

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = var.http_concurrent_requests
    }

    container {
      name   = "application"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name  = "SERVER_PORT"
        value = "4000"
      }

      env {
        name  = "DB_HOST"
        value = azurerm_postgresql_flexible_server.main.fqdn
      }

      env {
        name  = "DB_PORT"
        value = "5432"
      }

      env {
        name  = "DB_NAME"
        value = azurerm_postgresql_flexible_server_database.application.name
      }

      env {
        name        = "DB_USER_NAME"
        secret_name = "db-username"
      }

      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password"
      }

      # application.yaml appends this value to the JDBC URL. Encryption is
      # required even though the database is reachable only over private VNet.
      env {
        name  = "DB_OPTIONS"
        value = "?sslmode=require"
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 4000
        path                    = "/health"
        initial_delay           = 5
        interval_seconds        = 5
        timeout                 = 5
        failure_count_threshold = 30
      }

      # A TCP liveness probe checks that the process is accepting connections
      # without restarting healthy application replicas during a database outage.
      liveness_probe {
        transport               = "TCP"
        port                    = 4000
        initial_delay           = 30
        interval_seconds        = 15
        timeout                 = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 4000
        path                    = "/health/readiness"
        initial_delay           = 10
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 6
        success_count_threshold = 1
      }
    }
  }

  depends_on = [
    time_sleep.wait_for_container_app_key_vault_rbac,
    azurerm_postgresql_flexible_server_configuration.require_secure_transport,
  ]
}
