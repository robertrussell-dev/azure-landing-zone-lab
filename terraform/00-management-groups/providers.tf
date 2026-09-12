terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
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

# Used only for the hierarchy settings in tenant.tf, which azurerm has no
# resource for.
provider "azapi" {
  tenant_id = var.tenant_id
}
