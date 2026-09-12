# One spoke virtual network, its subnets, its route table and both halves of
# the peering with the hub.
#
# Everything in this module is free to leave running. Virtual networks,
# subnets, peerings, network security groups and route tables carry no hourly
# charge, which is the whole reason ADR 0004 chose hub and spoke over Virtual
# WAN for a lab on a personal card. The things that do bill are in the root
# module, behind flags.
#
# Subnets are derived from the spoke's own prefix rather than listed. That is
# not cleverness for its own sake: it makes it impossible to hand a spoke a
# subnet outside its allocation, which is the mistake an address plan exists to
# prevent.

locals {
  # A /22 splits into four /24s. Three are used and the fourth is carved
  # further, which matches the worked plan exactly.
  subnets = {
    app = {
      prefix = cidrsubnet(var.address_space, 2, 0)
      nsg    = true
    }
    data = {
      prefix = cidrsubnet(var.address_space, 2, 1)
      nsg    = true
    }
    privateendpoints = {
      prefix = cidrsubnet(var.address_space, 2, 2)
      nsg    = true
    }
    # Application Gateway v2 needs inbound 65200-65535 from GatewayManager or
    # it cannot be managed, so a baseline deny-all network security group here
    # would break the gateway rather than protect it. The subnet is reserved
    # and empty until something is actually deployed into it, and the rules
    # belong with that deployment.
    appgw = {
      prefix = cidrsubnet(var.address_space, 4, 12)
      nsg    = false
    }
  }

  # 0.0.0.0/0 to the firewall is forced tunnelling and applies to corp only.
  # An online spoke reaching the internet directly is the point of the
  # archetype, not an oversight.
  default_route = var.archetype == "corp" && var.firewall_private_ip != "" ? {
    default = "0.0.0.0/0"
  } : {}

  # Cross archetype routes apply to both, because peering is not transitive and
  # the firewall is the only path between spokes either way.
  peer_routes = var.firewall_private_ip == "" ? {} : {
    for prefix in var.peer_prefixes : "peer-${replace(prefix, "/[./]/", "-")}" => prefix
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags

  lifecycle {
    # Azure Policy owns costCenter. See terraform/25-brownfield-seed.
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_subnet" "this" {
  for_each = local.subnets

  # checkov:skip=CKV2_AZURE_31:Three of the four subnets are associated with the
  # baseline network security group below, through
  # azurerm_subnet_network_security_group_association. The graph check does not
  # follow that association across a module boundary, so it reports all four.
  # The fourth, snet-appgw, genuinely has none: Application Gateway v2 needs
  # inbound 65200-65535 from GatewayManager to stay manageable, so a baseline
  # deny group there would break the gateway rather than protect it. That subnet
  # is reserved and empty until a gateway is deployed with its own rules.

  name                 = "snet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefix]
}

# ---------------------------------------------------------------------------
# Baseline network security group
# ---------------------------------------------------------------------------
# Deliberately empty of custom rules. Azure's default rules already deny
# inbound from the internet and permit traffic within the virtual network, so
# an empty group is a working baseline rather than a placeholder. It exists
# here mainly so that every subnet that can carry one does, which is what the
# AuditIfNotExists assignment at the intermediate root is looking for.
resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = { for k, v in local.subnets : k => v if v.nsg }

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this.id
}

# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------
# The route table is created whether or not a firewall exists, so that turning
# the firewall on later adds routes rather than restructuring anything.
resource "azurerm_route_table" "this" {
  name                = "rt-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_route" "default" {
  for_each = local.default_route

  name                   = "to-firewall-default"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = each.value
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

resource "azurerm_route" "peer" {
  for_each = local.peer_routes

  name                   = each.key
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = each.value
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

# The Application Gateway subnet is left off the route table on purpose. A
# default route to a firewall breaks the gateway's control plane traffic, which
# Microsoft documents as a supported way to make an Application Gateway
# unmanageable.
resource "azurerm_subnet_route_table_association" "this" {
  for_each = { for k, v in local.subnets : k => v if k != "appgw" }

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.this.id
}

# ---------------------------------------------------------------------------
# Peering, both directions
# ---------------------------------------------------------------------------
# Peering is not transitive and it is not symmetrical to configure. Each side
# is its own resource and the flags mean different things depending on which
# end you are standing at.
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${var.name}-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.hub_virtual_network_id

  allow_virtual_network_access = true

  # Required for the firewall in the hub to forward traffic that did not
  # originate there, which is every spoke to spoke packet.
  allow_forwarded_traffic = true

  # The archetype, expressed as a peering flag. Azure rejects this outright if
  # the hub has no gateway, so the caller only sets it when one exists.
  use_remote_gateways = var.use_remote_gateways
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${var.name}"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = var.hub_virtual_network_name
  remote_virtual_network_id = azurerm_virtual_network.this.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true

  # The hub offers its gateway. Whether a spoke takes it up is decided on the
  # other side, by use_remote_gateways.
  allow_gateway_transit = true
}
