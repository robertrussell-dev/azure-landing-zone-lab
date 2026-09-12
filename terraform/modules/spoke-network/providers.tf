# The only module here that declares this, because it is the only one the
# caller hands an explicit provider to.
#
# 90-optional-network runs its default provider against the operator's own
# subscription and creates the network through an aliased one pointed at
# connectivity. Passing that alias into a module requires the module to say
# which provider name it expects, otherwise Terraform warns that it is guessing.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
