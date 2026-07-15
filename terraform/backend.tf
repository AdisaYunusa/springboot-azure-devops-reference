terraform {
  # The backend is intentionally configured using partial configuration.
  # Environment-specific storage details are supplied at `terraform init`
  # time through an uncommitted backend.hcl file.
  backend "azurerm" {}
}
