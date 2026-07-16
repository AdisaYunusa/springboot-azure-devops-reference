variable "subscription_id" {
  description = "Azure subscription ID in which the workload resources are created."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid Azure subscription UUID."
  }
}

variable "organisation" {
  description = "Short organisation identifier used in resource names."
  type        = string
  default     = "hmcts"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.organisation))
    error_message = "organisation must be 2-10 lowercase alphanumeric characters and begin with a letter."
  }
}

variable "workload" {
  description = "Short workload identifier used in resource names."
  type        = string
  default     = "devtest"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.workload))
    error_message = "workload must be 2-12 lowercase alphanumeric characters and begin with a letter."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "stg", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, stg, prod."
  }
}

variable "location" {
  description = "Azure region for workload resources."
  type        = string
  default     = "uksouth"
}

variable "region_code" {
  description = "Short region code used in resource names."
  type        = string
  default     = "uks"

  validation {
    condition     = can(regex("^[a-z0-9]{2,5}$", var.region_code))
    error_message = "region_code must be 2-5 lowercase alphanumeric characters."
  }
}

variable "owner" {
  description = "Team or individual accountable for the workload."
  type        = string
}

variable "repository" {
  description = "Source repository name or URL used for traceability tags."
  type        = string
}

variable "cost_centre" {
  description = "Cost allocation identifier."
  type        = string
  default     = "technical-assessment"
}

variable "data_classification" {
  description = "Data-classification tag applied to supported resources."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential, or restricted."
  }
}

variable "additional_tags" {
  description = "Additional tags merged with the mandatory governance tags."
  type        = map(string)
  default     = {}
}

variable "container_image" {
  description = "Immutable GHCR image reference. Use a full Git SHA tag or an OCI digest; latest is rejected."
  type        = string

  validation {
    condition = (
      can(regex("^ghcr\\.io/[a-z0-9._-]+/[a-z0-9._/-]+:sha-[0-9a-f]{40}$", lower(var.container_image))) ||
      can(regex("^ghcr\\.io/[a-z0-9._-]+/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$", lower(var.container_image)))
    )
    error_message = "container_image must use either :sha-<40-character Git SHA> or @sha256:<64-character digest>; mutable tags such as latest are not allowed."
  }
}

variable "container_cpu" {
  description = "vCPU allocated to the application container."
  type        = number
  default     = 0.5

  validation {
    condition     = contains([0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], var.container_cpu)
    error_message = "container_cpu must be a supported Azure Container Apps Consumption allocation."
  }
}

variable "container_memory" {
  description = "Memory allocated to the application container."
  type        = string
  default     = "1Gi"

  validation {
    condition     = contains(["0.5Gi", "1Gi", "1.5Gi", "2Gi", "3Gi", "3.5Gi", "4Gi"], var.container_memory)
    error_message = "container_memory must use a supported Azure Container Apps Consumption allocation."
  }
}

variable "container_min_replicas" {
  description = "Minimum number of warm application replicas."
  type        = number
  default     = 1

  validation {
    condition     = var.container_min_replicas >= 1
    error_message = "container_min_replicas must be at least 1 to avoid cold starts and provide availability."
  }
}

variable "container_max_replicas" {
  description = "Maximum number of application replicas."
  type        = number
  default     = 3

  validation {
    condition     = var.container_max_replicas >= 1 && var.container_max_replicas <= 30
    error_message = "container_max_replicas must be between 1 and 30."
  }
}

variable "http_concurrent_requests" {
  description = "Concurrent requests per replica that trigger HTTP autoscaling."
  type        = number
  default     = 50

  validation {
    condition     = var.http_concurrent_requests >= 1
    error_message = "http_concurrent_requests must be at least 1."
  }
}

variable "container_app_zone_redundancy_enabled" {
  description = "Enable zone redundancy for the Container Apps environment. Use true for production where the region supports it."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "log_daily_quota_gb" {
  description = "Daily Log Analytics ingestion cap in GB. Set to -1 for no cap."
  type        = number
  default     = 1

  validation {
    condition     = var.log_daily_quota_gb == -1 || var.log_daily_quota_gb >= 0.5
    error_message = "log_daily_quota_gb must be -1 or at least 0.5."
  }
}

variable "vnet_address_space" {
  description = "Address space for the workload virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]

  validation {
    condition     = length(var.vnet_address_space) > 0 && alltrue([for cidr in var.vnet_address_space : can(cidrnetmask(cidr))])
    error_message = "vnet_address_space must contain valid CIDR blocks."
  }
}

variable "container_apps_subnet_cidr" {
  description = "Dedicated subnet for the Container Apps environment. /27 or larger is required for the selected workload-profile environment."
  type        = string
  default     = "10.20.0.0/27"

  validation {
    condition     = can(cidrnetmask(var.container_apps_subnet_cidr)) && tonumber(split("/", var.container_apps_subnet_cidr)[1]) <= 27
    error_message = "container_apps_subnet_cidr must be a valid CIDR with a prefix of /27 or larger."
  }
}

variable "postgresql_subnet_cidr" {
  description = "Dedicated delegated subnet for PostgreSQL Flexible Server."
  type        = string
  default     = "10.20.1.0/27"

  validation {
    condition     = can(cidrnetmask(var.postgresql_subnet_cidr)) && tonumber(split("/", var.postgresql_subnet_cidr)[1]) <= 27
    error_message = "postgresql_subnet_cidr must be a valid CIDR with a prefix of /27 or larger."
  }
}

variable "key_vault_deployer_ip_rules" {
  description = "Public IPv4 addresses permitted to administer Key Vault during Terraform execution. The assessment assumes one approved public egress IP, but the list supports additional individual addresses if required."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.key_vault_deployer_ip_rules :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) &&
      can(cidrnetmask("${ip}/32"))
    ])

    error_message = "Every key_vault_deployer_ip_rules entry must be an individual IPv4 address without CIDR notation."
  }
}

variable "postgresql_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["14", "15", "16", "17", "18"], var.postgresql_version)
    error_message = "postgresql_version must be a currently supported major version from 14 to 18."
  }
}

variable "postgresql_sku_name" {
  description = "Azure PostgreSQL Flexible Server SKU."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL storage size in MB."
  type        = number
  default     = 32768

  validation {
    condition = contains([
      32768, 65536, 131072, 262144, 524288, 1048576,
      2097152, 4193280, 4194304, 8388608, 16777216, 33553408
    ], var.postgresql_storage_mb)
    error_message = "postgresql_storage_mb must be one of the sizes supported by Azure PostgreSQL Flexible Server."
  }
}

variable "postgresql_database_name" {
  description = "Application PostgreSQL database name."
  type        = string
  default     = "devtest"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.postgresql_database_name))
    error_message = "postgresql_database_name must begin with a lowercase letter and contain only lowercase letters, numbers, or underscores."
  }
}

variable "postgresql_administrator_login" {
  description = "PostgreSQL administrator username. Stored in Key Vault and supplied to the application as a secret reference."
  type        = string
  default     = "devtestadmin"

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9_]{2,62}$", var.postgresql_administrator_login)) &&
      !contains(["admin", "administrator", "azure_superuser", "azure_pg_admin", "root", "guest", "public"], var.postgresql_administrator_login)
    )
    error_message = "postgresql_administrator_login must be 3-63 lowercase characters and must not use a reserved administrative name."
  }
}

variable "postgresql_password_version" {
  description = "Rotation counter for the write-only PostgreSQL password. Increment to generate and apply a new password."
  type        = number
  default     = 1

  validation {
    condition     = var.postgresql_password_version >= 1 && floor(var.postgresql_password_version) == var.postgresql_password_version
    error_message = "postgresql_password_version must be a positive integer."
  }
}

variable "postgresql_backup_retention_days" {
  description = "Point-in-time backup retention."
  type        = number
  default     = 7

  validation {
    condition     = var.postgresql_backup_retention_days >= 7 && var.postgresql_backup_retention_days <= 35
    error_message = "postgresql_backup_retention_days must be between 7 and 35."
  }
}

variable "postgresql_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant PostgreSQL backups. This increases resilience and cost."
  type        = bool
  default     = false
}

variable "postgresql_high_availability_enabled" {
  description = "Enable zone-redundant PostgreSQL high availability."
  type        = bool
  default     = false
}

variable "postgresql_maintenance_day" {
  description = "Weekly maintenance day in UTC where Sunday is 0."
  type        = number
  default     = 0

  validation {
    condition     = var.postgresql_maintenance_day >= 0 && var.postgresql_maintenance_day <= 6
    error_message = "postgresql_maintenance_day must be between 0 and 6."
  }
}

variable "postgresql_maintenance_hour" {
  description = "Maintenance-window start hour in UTC."
  type        = number
  default     = 3

  validation {
    condition     = var.postgresql_maintenance_hour >= 0 && var.postgresql_maintenance_hour <= 23
    error_message = "postgresql_maintenance_hour must be between 0 and 23."
  }
}
