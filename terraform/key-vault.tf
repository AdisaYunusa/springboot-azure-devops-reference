resource "azurerm_key_vault" "main" {
  name                = local.names.key_vault
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = true

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.key_vault_deployer_ip_cidrs
    virtual_network_subnet_ids = [azurerm_subnet.container_apps.id]
  }

  tags = local.common_tags
}

# Terraform needs data-plane permission to write the generated credentials.
# The assignment is scoped to this vault rather than the whole subscription.
resource "azurerm_role_assignment" "terraform_key_vault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The application receives read-only access to secret values through managed
# identity. No static Azure credential is placed in the container.
resource "azurerm_role_assignment" "container_app_key_vault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.container_app.principal_id
}

# Azure RBAC assignments can take a short period to become effective. Waiting
# here prevents an otherwise valid first apply from failing while the data-plane
# permission propagates.
resource "time_sleep" "wait_for_key_vault_rbac" {
  create_duration = "30s"

  depends_on = [
    azurerm_role_assignment.terraform_key_vault_secrets_officer,
  ]
}

resource "time_sleep" "wait_for_container_app_key_vault_rbac" {
  create_duration = "30s"

  depends_on = [
    azurerm_role_assignment.container_app_key_vault_secrets_user,
  ]
}

# The username is stored as a Key Vault secret so the application receives both
# database credentials through one consistent secret-reference pattern.
resource "azurerm_key_vault_secret" "postgresql_username" {
  name         = "postgresql-administrator-username"
  value        = var.postgresql_administrator_login
  key_vault_id = azurerm_key_vault.main.id
  content_type = "text/plain"
  tags         = local.common_tags

  depends_on = [
    time_sleep.wait_for_key_vault_rbac,
  ]
}

# Terraform 1.15 ephemeral resources and AzureRM write-only arguments prevent
# the generated password from being persisted in Terraform plan or state.
ephemeral "random_password" "postgresql_administrator" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "postgresql_password" {
  name             = "postgresql-administrator-password"
  value_wo         = ephemeral.random_password.postgresql_administrator.result
  value_wo_version = local.database_password_version
  key_vault_id     = azurerm_key_vault.main.id
  content_type     = "password"
  tags             = local.common_tags

  depends_on = [
    time_sleep.wait_for_key_vault_rbac,
  ]
}

# Read the persisted Key Vault value only ephemerally so that the exact same
# password is supplied to PostgreSQL without Terraform storing it.
ephemeral "azurerm_key_vault_secret" "postgresql_password" {
  name         = azurerm_key_vault_secret.postgresql_password.name
  key_vault_id = azurerm_key_vault.main.id
}
