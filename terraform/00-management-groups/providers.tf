terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}

# Management groups are tenant scoped resources, but the azurerm provider has
# required an explicit subscription_id since version 4.0. Setting subscription_id
# and tenant_id here is also a safety measure: the operator's CLI profile may hold
# credentials for more than one tenant, and pinning both values means a stray
# "az account set" cannot cause an apply against the wrong tenant.
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
