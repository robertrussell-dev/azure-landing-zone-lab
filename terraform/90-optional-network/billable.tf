# Everything in this file bills by the hour. All off by default; each flag's
# price is in variables.tf, and standing_monthly_cost_usd totals what's on.
#
# Each resource is tagged deleteAfter, billable_ttl_hours after creation, and
# terraform/30-auto-delete removes it after that. ignore_changes keeps the first
# value, so the window doesn't move on later plans.

locals {
  delete_after = timeadd(plantimestamp(), "${var.billable_ttl_hours}h")
}

# ---------------------------------------------------------------------------
# Azure Firewall
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
  }
}

resource "azurerm_firewall_policy" "hub" {
  provider = azurerm.connectivity
  count    = var.deploy_firewall ? 1 : 0

  name                = "afwp-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = var.firewall_sku_tier

  # Deny instead of the Alert default. The firewall inherits it from the policy.
  # azurerm rejects threat_intel_mode on the firewall alongside a policy, so
  # unlike the Bicep tree it's only set here.
  threat_intelligence_mode = "Deny"

  tags = {
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
  }
}

# ---------------------------------------------------------------------------
# VPN gateway
# ---------------------------------------------------------------------------
# 30 to 45 minutes to create, and the same to destroy.
resource "azurerm_public_ip" "vpn" {
  provider = azurerm.connectivity
  count    = var.deploy_vpn_gateway ? 1 : 0

  name                = "pip-vgw-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
  }
}

# ---------------------------------------------------------------------------
# ExpressRoute gateway
# ---------------------------------------------------------------------------
# The gateway only; the circuit is a carrier contract. It shares GatewaySubnet
# with the VPN gateway, which is why that subnet is a /26.
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
  }
}

# ---------------------------------------------------------------------------
# Azure Bastion
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
  }
}

# ---------------------------------------------------------------------------
# Azure Route Server
# ---------------------------------------------------------------------------
# Only useful with a BGP speaking appliance peering with it, which this lab
# doesn't have. It's here because the address plan has its subnet.
resource "azurerm_public_ip" "route_server" {
  provider = azurerm.connectivity
  count    = var.deploy_route_server ? 1 : 0

  name                = "pip-rs-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
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
    autoDelete  = "true"
    deleteAfter = local.delete_after
  }

  lifecycle {
    ignore_changes = [tags["costCenter"], tags["deleteAfter"]]
  }
}

# ---------------------------------------------------------------------------
# A budget on the subscription that holds all of this
# ---------------------------------------------------------------------------
# Always created, since its job is catching a device someone forgot.
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
