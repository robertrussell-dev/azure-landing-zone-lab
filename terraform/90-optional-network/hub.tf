# The hub virtual network, and every subnet the worked address plan calls for.
#
# The plan this implements is docs/ip-plan.md. Nothing here is invented: the
# prefixes, the subnet names and the sizes all come from that document, and the
# derivations below are what prove the plan is systematic rather than a list of
# numbers that happen not to collide.
#
# Everything in this file is free. A virtual network with ten subnets in it
# costs nothing per hour, which is what makes it reasonable to leave the shape
# of the network deployed permanently and bring only the appliances up on
# demand.
#
# Four of these subnet names are mandatory and case sensitive. Azure will not
# attach the service if they are spelled anything else, and the failure is a
# deployment error rather than a warning.

resource "azurerm_resource_group" "hub" {
  provider = azurerm.connectivity

  name     = "rg-hub-network"
  location = var.location

  tags = {
    autoDelete = "false"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_virtual_network" "hub" {
  provider = azurerm.connectivity

  name                = "vnet-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  address_space       = [var.hub_address_space]

  tags = {
    autoDelete = "false"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

locals {
  # The four mandatory /26s tile the first /24 of the hub exactly. That is
  # deliberate in the plan and it survives here because every prefix is
  # derived from hub_address_space rather than typed.
  #
  # RouteServerSubnet is a /26, not the /27 that older material and one
  # surviving Microsoft tutorial still show. A /27 fails at create time, and
  # widening it to /26 is what pushed the DNS resolver endpoints from
  # 10.0.1.32 and 10.0.1.48 up to 10.0.1.64 and 10.0.1.80.
  hub_subnets = {
    GatewaySubnet = {
      prefix     = cidrsubnet(var.hub_address_space, 6, 0)
      delegation = null
    }
    AzureFirewallSubnet = {
      prefix     = cidrsubnet(var.hub_address_space, 6, 1)
      delegation = null
    }
    AzureFirewallManagementSubnet = {
      prefix     = cidrsubnet(var.hub_address_space, 6, 2)
      delegation = null
    }
    AzureBastionSubnet = {
      prefix     = cidrsubnet(var.hub_address_space, 6, 3)
      delegation = null
    }
    RouteServerSubnet = {
      prefix     = cidrsubnet(var.hub_address_space, 6, 4)
      delegation = null
    }
    snet-dns-inbound = {
      prefix     = cidrsubnet(var.hub_address_space, 8, 20)
      delegation = "Microsoft.Network/dnsResolvers"
    }
    snet-dns-outbound = {
      prefix     = cidrsubnet(var.hub_address_space, 8, 21)
      delegation = "Microsoft.Network/dnsResolvers"
    }
    snet-shared-privateendpoints = {
      prefix     = cidrsubnet(var.hub_address_space, 4, 2)
      delegation = null
    }
    snet-shared-services = {
      prefix     = cidrsubnet(var.hub_address_space, 4, 3)
      delegation = null
    }
  }
}

resource "azurerm_subnet" "hub" {
  provider = azurerm.connectivity
  for_each = local.hub_subnets

  # checkov:skip=CKV2_AZURE_31:Four of these subnets cannot or should not carry
  # a network security group. AzureFirewallSubnet and
  # AzureFirewallManagementSubnet do not support one at all and Azure rejects
  # the association. RouteServerSubnet does not support one either.
  # AzureBastionSubnet supports one only with a specific rule set that is
  # meaningless until Bastion exists, and a wrong rule there breaks the service
  # rather than protecting it. GatewaySubnet accepts one and Microsoft advises
  # against it for the same reason. Every subnet that can safely carry the
  # baseline group is associated with it above.

  name                 = each.key
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value.prefix]

  # The DNS Private Resolver endpoints need delegated subnets and cannot share
  # them with anything else.
  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = "delegation"
      service_delegation {
        name = delegation.value
      }
    }
  }
}

# Four subnets get the baseline network security group: the two general purpose
# ones and both DNS resolver endpoints. Delegation does not prevent a subnet
# from carrying one.
#
# The other five do not, and cannot safely. AzureFirewallSubnet,
# AzureFirewallManagementSubnet and RouteServerSubnet do not support one at all.
# AzureBastionSubnet supports one only with a specific rule set that is
# meaningless until Bastion exists. GatewaySubnet accepts one and Microsoft
# advises against it, because the wrong rule breaks the control plane. So the
# subnets left without one are left that way on purpose, and the audit
# assignment at the intermediate root will report them.
resource "azurerm_network_security_group" "hub_shared" {
  provider = azurerm.connectivity

  name                = "nsg-hub-shared"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location

  tags = {
    autoDelete = "false"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_subnet_network_security_group_association" "hub_shared" {
  provider = azurerm.connectivity
  for_each = toset([
    "snet-shared-privateendpoints",
    "snet-shared-services",
    # Delegated subnets can still carry a network security group, and the
    # resolver endpoints are the only delegated ones here, so they get the
    # baseline too.
    "snet-dns-inbound",
    "snet-dns-outbound",
  ])

  subnet_id                 = azurerm_subnet.hub[each.key].id
  network_security_group_id = azurerm_network_security_group.hub_shared.id
}
