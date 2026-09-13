# One spoke: virtual network, subnets, route table, and both halves of the hub
# peering. All free. Subnets are derived from the spoke's prefix, so none can
# fall outside it.

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
    # Application Gateway v2 needs inbound 65200-65535 from GatewayManager, so
    # its rules belong with the gateway. Empty until one is deployed.
    appgw = {
      prefix = cidrsubnet(var.address_space, 4, 12)
      nsg    = false
    }
  }

  # 0.0.0.0/0 to the firewall is forced tunneling and applies to corp only.
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

  # checkov:skip=CKV2_AZURE_31:Three subnets get the baseline network security
  # group through the association below, which this check cannot follow across
  # a module boundary. The fourth, snet-appgw, has none; see locals.

  name                 = "snet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefix]
}

# ---------------------------------------------------------------------------
# Baseline network security group
# ---------------------------------------------------------------------------
# No custom rules. Azure's defaults already deny inbound internet traffic and
# allow traffic inside the virtual network.
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
# Created even without a firewall, so enabling one only adds routes.
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

# Not on snet-appgw: a default route to a firewall breaks Application Gateway's
# control plane traffic.
resource "azurerm_subnet_route_table_association" "this" {
  for_each = { for k, v in local.subnets : k => v if k != "appgw" }

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.this.id
}

# ---------------------------------------------------------------------------
# Peering, both directions
# ---------------------------------------------------------------------------
# Each side of a peering is its own resource, and the flags mean different
# things at each end.
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

# ---------------------------------------------------------------------------
# Policy exemption for snet-appgw
# ---------------------------------------------------------------------------
# A Waiver with an expiry, because the network security group comes with a
# future gateway.
resource "azurerm_resource_policy_exemption" "appgw_no_nsg" {
  count = var.subnet_nsg_policy_assignment_id == "" ? 0 : 1

  name                 = "exempt-nsg-appgw-${var.name}"
  display_name         = "snet-appgw in ${var.name} has no network security group until a gateway is deployed"
  description          = "Application Gateway v2 needs inbound 65200-65535 from GatewayManager, so the baseline group would break it. The rules belong with the gateway deployment."
  resource_id          = azurerm_subnet.this["appgw"].id
  policy_assignment_id = var.subnet_nsg_policy_assignment_id
  exemption_category   = "Waiver"
  expires_on           = var.appgw_waiver_expires_on
}
