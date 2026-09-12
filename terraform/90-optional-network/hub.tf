# The hub virtual network and every subnet in docs/ip-plan.md.
#
# Every prefix is derived from hub_address_space rather than typed, which is
# what proves the plan is systematic rather than numbers that happen not to
# collide. Everything in this file is free to leave running.
#
# Five of the subnet names are mandatory and case sensitive: Azure will not
# attach the service to a subnet spelled any other way.

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
  # The first four /26s tile the first /24 of the hub exactly. RouteServerSubnet
  # is also a /26, not the /27 some older material shows: a /27 fails at create
  # time. The DNS resolver endpoints start after it, at 10.0.1.64.
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

  # checkov:skip=CKV2_AZURE_31:Five of these subnets must not carry the baseline
  # network security group. The comment on hub_shared below says why.

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

# The baseline network security group goes on the four subnets that can safely
# carry one: the two general purpose ones and both DNS resolver endpoints
# (delegation does not prevent it). The other five cannot. AzureFirewallSubnet,
# AzureFirewallManagementSubnet and RouteServerSubnet do not support one.
# AzureBastionSubnet needs a specific rule set that is meaningless until Bastion
# exists, and GatewaySubnet accepts one but Microsoft advises against it,
# because a wrong rule breaks the control plane. The audit assignment at the
# intermediate root reports all five, correctly.
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
