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

# The network lands in the connectivity subscription, through an aliased
# provider, for the same reason the workspace in 20-subscription-placement
# does: the default provider is the operator's own subscription and a hub
# deployed there instead would be a quiet, expensive mistake to find later.
provider "azurerm" {
  alias = "connectivity"
  features {}

  subscription_id = var.connectivity_subscription_id
  tenant_id       = var.tenant_id
}
