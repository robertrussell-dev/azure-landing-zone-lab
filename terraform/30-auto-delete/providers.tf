terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

# The role definition and its assignment are management group resources, which
# this provider reaches regardless of the subscription it is pinned to.
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# The Automation account lives in the management subscription, next to the
# workspace, and is created through an alias for the same reason the workspace
# is: the default provider is the operator's own subscription.
provider "azurerm" {
  alias = "management"
  features {}

  subscription_id = var.management_subscription_id
  tenant_id       = var.tenant_id

  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Automation"]
}
