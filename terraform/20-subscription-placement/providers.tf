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

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Resources inside the management subscription are created through this
# aliased provider. The default provider is pinned to the operator's own
# subscription, and a workspace deployed there instead would be a quiet,
# hard to spot mistake.
provider "azurerm" {
  alias = "management"
  features {}

  subscription_id = var.management_subscription_id
  tenant_id       = var.tenant_id
}
