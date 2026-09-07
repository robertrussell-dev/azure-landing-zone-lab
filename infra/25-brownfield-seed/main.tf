# Deliberately non compliant resources, created on purpose.
#
# Read this before assuming it is a mistake.
#
# The brownfield adoption pattern in ADR 0005 only demonstrates anything if the
# adopted subscription actually violates the policies it is being measured
# against. An empty subscription reports no compliance state at all, because
# there is nothing to evaluate, which makes the audit only assignment look like
# it is not working when it is simply not applicable to anything.
#
# In a real engagement these violations already exist and nobody had to create
# them. Here they are seeded, and the README says so rather than implying an
# inherited mess.
#
# Everything below is free. Virtual networks, subnets and network security
# groups carry no hourly charge. Nothing here needs destroying for cost
# reasons, which is why it is not part of the Phase 4 deploy and destroy stack.

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

# Violation 1: a subnet with no network security group attached.
#
# Trips "Subnets should be associated with a Network Security Group", assigned
# as AuditIfNotExists at the intermediate root. Reports, never blocks, so this
# is non compliant everywhere in the hierarchy rather than only under the audit
# only archetype.
resource "azurerm_virtual_network" "seed" {
  provider = azurerm.brownfield

  name                = "vnet-legacy-app"
  resource_group_name = azurerm_resource_group.seed.name
  location            = azurerm_resource_group.seed.location
  address_space       = ["10.240.0.0/24"]

  tags = {
    autoDelete = "true"
  }
}

resource "azurerm_subnet" "no_nsg" {
  provider = azurerm.brownfield

  name                 = "snet-no-nsg"
  resource_group_name  = azurerm_resource_group.seed.name
  virtual_network_name = azurerm_virtual_network.seed.name
  address_prefixes     = ["10.240.0.0/26"]

  # No network_security_group_association resource, on purpose. That absence is
  # the whole point of this file.
}

# Violation 2: a network interface carrying a public IP.
#
# Trips "Network interfaces should not have public IPs", the Deny assigned at
# Corp. Because this subscription sits under Corp (audit only) with
# enforcementMode DoNotEnforce, creating this succeeds and is recorded as non
# compliant. Under Corp it would be refused outright.
#
# That contrast is the single most useful thing in this repository to look at:
# the same policy, the same resource, different enforcement, decided purely by
# where the subscription sits.
#
# This one is not free. A Standard static public IP is about 0.005 USD per
# hour, roughly 3.60 USD per month, verified against the retail prices API on
# 2026-09-06. It is the only billable resource in the lab and exists solely to
# make the Deny demonstrable.
resource "azurerm_public_ip" "seed" {
  provider = azurerm.brownfield

  name                = "pip-legacy-app"
  resource_group_name = azurerm_resource_group.seed.name
  location            = azurerm_resource_group.seed.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    autoDelete = "true"
  }
}

resource "azurerm_network_interface" "seed" {
  provider = azurerm.brownfield

  name                = "nic-legacy-app"
  resource_group_name = azurerm_resource_group.seed.name
  location            = azurerm_resource_group.seed.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.no_nsg.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.seed.id
  }

  tags = {
    autoDelete = "true"
  }
}
