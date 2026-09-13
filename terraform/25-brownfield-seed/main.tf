# Resources that break the policy set, so the audit only assignment from ADR
# 0005 has something to report. A real adoption would already have these.
# All free.

# ---------------------------------------------------------------------------
# Who owns the costCenter tag
# ---------------------------------------------------------------------------
# The Modify assignment appends costCenter. Without ignore_changes, every plan
# would try to remove it. Policy owns the field, so Terraform ignores it.

resource "azurerm_resource_group" "seed" {
  provider = azurerm.brownfield

  name     = "rg-legacy-app"
  location = var.location

  # No costCenter, so the Modify assignment has something to add.
  tags = {
    autoDelete = "true"
  }
}

# The violation: a subnet with no network security group, reported by the
# AuditIfNotExists assignment.
resource "azurerm_virtual_network" "seed" {
  provider = azurerm.brownfield

  name                = "vnet-legacy-app"
  resource_group_name = azurerm_resource_group.seed.name
  location            = azurerm_resource_group.seed.location
  address_space       = ["10.240.0.0/24"]

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    # Policy owns costCenter.
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_subnet" "no_nsg" {
  provider = azurerm.brownfield

  # checkov:skip=CKV2_AZURE_31:This subnet is the policy violation being seeded.

  name                 = "snet-no-nsg"
  resource_group_name  = azurerm_resource_group.seed.name
  virtual_network_name = azurerm_virtual_network.seed.name
  address_prefixes     = ["10.240.0.0/26"]
}
