# Everything in this file bills by the hour from the moment it exists.
#
# Nothing here is on by default. Each flag names its own price in
# variables.tf, and the standing_monthly_cost output adds up whatever is
# currently switched on so the number is visible in a plan rather than
# discovered on an invoice.
#
# The discipline this is built for is the one the README already describes:
# bring a device up, capture whatever you needed it for, destroy it the same
# day. A gateway left running over a weekend costs more than everything else
# in this repository has cost in total.
#
# Prices are West US 2, USD, retail, checked against the Azure retail prices
# API on 2026-09-12.

# ---------------------------------------------------------------------------
# Azure Firewall, about 912 per month on Standard
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "firewall" {
  provider = azurerm.connectivity
  count    = var.deploy_firewall ? 1 : 0

  name                = "pip-fw-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location

  # Azure Firewall requires Standard SKU and static allocation.
  allocation_method = "Static"
  sku               = "Standard"

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_firewall_policy" "hub" {
  provider = azurerm.connectivity
  count    = var.deploy_firewall ? 1 : 0

  name                = "afwp-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = var.firewall_sku_tier

  # Deny rather than the Alert default. With a policy attached the firewall
  # inherits threat intelligence settings from it, so this is where the setting
  # takes effect.
  #
  # The Bicep tree also sets threatIntelMode on the firewall resource itself.
  # This one does not, because azurerm conflicts threat_intel_mode with
  # firewall_policy_id and setting both is a apply time error rather than a
  # redundancy. Same outcome, different place to write it.
  threat_intelligence_mode = "Deny"

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_firewall" "hub" {
  provider = azurerm.connectivity
  count    = var.deploy_firewall ? 1 : 0

  name                = "afw-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.hub[0].id

  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.hub["AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

# ---------------------------------------------------------------------------
# VPN gateway, about 139 per month on VpnGw1
# ---------------------------------------------------------------------------
# Slow to create and slow to destroy, 30 to 45 minutes each way. That is worth
# knowing before planning a same day teardown around it.
resource "azurerm_public_ip" "vpn" {
  provider = azurerm.connectivity
  count    = var.deploy_vpn_gateway ? 1 : 0

  name                = "pip-vgw-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_virtual_network_gateway" "vpn" {
  provider = azurerm.connectivity
  count    = var.deploy_vpn_gateway ? 1 : 0

  name                = "vgw-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location

  type     = "Vpn"
  vpn_type = "RouteBased"
  sku      = "VpnGw1"

  ip_configuration {
    name                 = "default"
    subnet_id            = azurerm_subnet.hub["GatewaySubnet"].id
    public_ip_address_id = azurerm_public_ip.vpn[0].id
  }

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

# ---------------------------------------------------------------------------
# ExpressRoute gateway, about 139 per month on Standard
# ---------------------------------------------------------------------------
# The gateway only. The circuit is a carrier contract and is not something this
# repository can or should create.
#
# It shares GatewaySubnet with the VPN gateway, which is why the plan gives
# that subnet a /26 rather than the /27 minimum: coexistence needs the room.
resource "azurerm_virtual_network_gateway" "expressroute" {
  provider = azurerm.connectivity
  count    = var.deploy_expressroute_gateway ? 1 : 0

  name                = "ergw-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location

  type = "ExpressRoute"
  sku  = "Standard"

  ip_configuration {
    name      = "default"
    subnet_id = azurerm_subnet.hub["GatewaySubnet"].id

    # An ExpressRoute gateway still needs a public IP object, even though no
    # traffic reaches it over the internet.
    public_ip_address_id = azurerm_public_ip.expressroute[0].id
  }

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_public_ip" "expressroute" {
  provider = azurerm.connectivity
  count    = var.deploy_expressroute_gateway ? 1 : 0

  name                = "pip-ergw-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

# ---------------------------------------------------------------------------
# Azure Bastion, about 212 per month on Standard
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "bastion" {
  provider = azurerm.connectivity
  count    = var.deploy_bastion ? 1 : 0

  name                = "pip-bas-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_bastion_host" "hub" {
  provider = azurerm.connectivity
  count    = var.deploy_bastion ? 1 : 0

  name                = "bas-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = "Standard"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.hub["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

# ---------------------------------------------------------------------------
# Azure Route Server, about 73 per month
# ---------------------------------------------------------------------------
# Only earns its place if a BGP speaking network virtual appliance is peering
# with it, and there is not one here. It exists so the subnet in the address
# plan has something to justify it.
resource "azurerm_public_ip" "route_server" {
  provider = azurerm.connectivity
  count    = var.deploy_route_server ? 1 : 0

  name                = "pip-rs-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_route_server" "hub" {
  provider = azurerm.connectivity
  count    = var.deploy_route_server ? 1 : 0

  name                             = "rs-hub"
  resource_group_name              = azurerm_resource_group.hub.name
  location                         = azurerm_resource_group.hub.location
  sku                              = "Standard"
  public_ip_address_id             = azurerm_public_ip.route_server[0].id
  subnet_id                        = azurerm_subnet.hub["RouteServerSubnet"].id
  branch_to_branch_traffic_enabled = false

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    ignore_changes = [tags["costCenter"]]
  }
}

# ---------------------------------------------------------------------------
# A budget on the subscription that holds all of this
# ---------------------------------------------------------------------------
# Created whether or not anything billable is switched on, because the point of
# it is to catch the case where something was switched on and forgotten.
module "budget" {
  source = "../modules/subscription-budget"
  count  = length(var.budget_alert_emails) > 0 ? 1 : 0

  name            = "budget-connectivity"
  subscription_id = var.connectivity_subscription_id
  amount          = var.monthly_budget_amount
  contact_emails  = var.budget_alert_emails

  # Forecast fires before the money is gone, which for a gateway left running
  # is the only alert that helps.
  actual_threshold_percent   = 50
  forecast_threshold_percent = 80
}
