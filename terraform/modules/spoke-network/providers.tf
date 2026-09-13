# Declared because 90-optional-network passes this module an aliased provider,
# and Terraform warns unless the module names what it expects.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
