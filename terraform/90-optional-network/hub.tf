# The hub virtual network and every subnet in docs/ip-plan.md.
#
# Every prefix is derived from hub_address_space, not typed. All free.
#
# Five subnet names are mandatory and case sensitive.

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
        # Azure adds this action to the delegation itself. Declaring it keeps
        # every later plan from trying to remove it again.
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}

# The baseline network security group goes on four subnets: the two general
# purpose ones and both DNS resolver endpoints. The firewall, firewall
# management and Route Server subnets don't support one, Bastion needs its own
# rules, and Microsoft advises against one on GatewaySubnet. Those five are
# exempted below.
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

# ---------------------------------------------------------------------------
# Policy exemptions
# ---------------------------------------------------------------------------
# The subnet audit flags the five platform subnets above. Exemptions record why
# in the compliance view. Mitigated, because each owning service protects its
# subnet.
locals {
  subnet_nsg_assignment_id = "/providers/Microsoft.Management/managementGroups/${var.prefix}/providers/Microsoft.Authorization/policyAssignments/audit-subnet-nsg"

  subnets_without_nsg = toset([
    "GatewaySubnet",
    "AzureFirewallSubnet",
    "AzureFirewallManagementSubnet",
    "AzureBastionSubnet",
    "RouteServerSubnet",
  ])
}

resource "azurerm_resource_policy_exemption" "hub_no_nsg" {
  provider = azurerm.connectivity
  for_each = local.subnets_without_nsg

  name                 = "exempt-nsg-${lower(each.key)}"
  display_name         = "${each.key} cannot carry the baseline network security group"
  description          = "Azure either rejects a network security group on this subnet or advises against one, and the service that owns it provides its own protection."
  resource_id          = azurerm_subnet.hub[each.key].id
  policy_assignment_id = local.subnet_nsg_assignment_id
  exemption_category   = "Mitigated"
}
