# Deliberately non compliant resources, created on purpose.
#
# ADR 0005's audit only adoption only shows anything if the adopted subscription
# actually breaks the policies it is measured against. An empty subscription
# reports no compliance state at all. In a real engagement the violations
# already exist; here they are seeded. Everything below is free.

# ---------------------------------------------------------------------------
# Who owns the costCenter tag
# ---------------------------------------------------------------------------
# The Modify assignment at the intermediate root appends costCenter to anything
# created without it. Terraform would read the tag back, find it missing from
# the configuration, and plan to remove it on every run while the policy keeps
# putting it back. Azure Policy owns the field, so Terraform ignores it. The
# same trade-off applies to every Modify assignment, which is why they should
# be few.

resource "azurerm_resource_group" "seed" {
  provider = azurerm.brownfield

  name     = "rg-legacy-app"
  location = var.location

  # Deliberately missing costCenter. The Modify assignment at the intermediate
  # root appends it to resources that lack it, so this is also the test of
  # whether that assignment does what it claims.
  tags = {
    autoDelete = "true"
  }
}

# The violation: a subnet with no network security group. It trips the
# AuditIfNotExists assignment at the intermediate root, which reports and never
# blocks, so it is non compliant everywhere in the hierarchy.
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
    # Azure Policy owns costCenter. See the note above.
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_subnet" "no_nsg" {
  provider = azurerm.brownfield

  # checkov:skip=CKV2_AZURE_31:No network security group on purpose. This
  # subnet exists to give the AuditIfNotExists assignment a real finding.

  name                 = "snet-no-nsg"
  resource_group_name  = azurerm_resource_group.seed.name
  virtual_network_name = azurerm_virtual_network.seed.name
  address_prefixes     = ["10.240.0.0/26"]

  # No network_security_group_association resource, on purpose. That absence is
  # the whole point of this file.
}
