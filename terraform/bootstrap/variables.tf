variable "subscription_id" {
  description = "Azure subscription ID for the Terraform state resources."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a valid Azure subscription UUID."
  }
}

variable "location" {
  description = "Azure region for state resources."
  type        = string
  default     = "uksouth"
}

variable "organisation" {
  description = "Short organisation identifier."
  type        = string
  default     = "hmcts"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.organisation))
    error_message = "organisation must be 2-10 lowercase alphanumeric characters and begin with a letter."
  }
}

variable "region_code" {
  description = "Short region identifier."
  type        = string
  default     = "uks"

  validation {
    condition     = can(regex("^[a-z0-9]{2,5}$", var.region_code))
    error_message = "region_code must be 2-5 lowercase alphanumeric characters."
  }
}

variable "owner" {
  description = "Team accountable for the Terraform state platform."
  type        = string
}

variable "repository" {
  description = "Repository that consumes this backend."
  type        = string
}

variable "backend_allowed_ip_cidrs" {
  description = "Public IPv4 CIDRs permitted to access the Terraform state storage account."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.backend_allowed_ip_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every backend_allowed_ip_cidrs entry must be a valid CIDR."
  }
}

variable "state_container_name" {
  description = "Blob container used for Terraform state."
  type        = string
  default     = "tfstate"
}

variable "state_delete_retention_days" {
  description = "Soft-delete retention for blobs and containers."
  type        = number
  default     = 30

  validation {
    condition     = var.state_delete_retention_days >= 7 && var.state_delete_retention_days <= 365
    error_message = "state_delete_retention_days must be between 7 and 365."
  }
}

variable "additional_tags" {
  description = "Additional governance tags."
  type        = map(string)
  default     = {}
}
