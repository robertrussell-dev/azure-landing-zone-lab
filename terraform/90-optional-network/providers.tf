terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# An aliased provider for the connectivity subscription, so nothing lands in the
# operator's default subscription by mistake.
provider "azurerm" {
  alias = "connectivity"
  features {}

  subscription_id = var.connectivity_subscription_id
  tenant_id       = var.tenant_id

  # A freshly vended subscription has no resource providers registered, and
  # nothing here can be created until Microsoft.Network is. Registering costs
  # nothing, and doing it here means a new subscription needs no manual step.
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Network"]
}
