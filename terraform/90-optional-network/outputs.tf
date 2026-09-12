output "hub_subnet_prefixes" {
  description = "The hub subnet layout as actually derived, so it can be diffed against docs/ip-plan.md without reading state."
  value       = { for k, v in local.hub_subnets : k => v.prefix }
}

output "spoke_subnet_prefixes" {
  description = "Every spoke's derived subnets, same purpose."
  value       = { for k, v in module.spoke : k => v.subnet_prefixes }
}

output "archetype_enforcement" {
  description = "Which spokes can reach on premises through the hub gateway, and which cannot. This is the ADR 0003 decision as the deployment actually implements it, rather than as the names suggest."
  value = {
    for k, v in var.spokes : k => {
      archetype           = v.archetype
      gateway_transit     = v.archetype == "corp" && (var.deploy_vpn_gateway || var.deploy_expressroute_gateway)
      default_route_to_fw = v.archetype == "corp" && var.deploy_firewall
    }
  }
}

# ---------------------------------------------------------------------------
# What this currently costs to leave running
# ---------------------------------------------------------------------------
# Retail, West US 2, USD, checked against the Azure retail prices API on
# 2026-09-12. Surfacing it as an output means the number shows up in a plan,
# before the apply, rather than on an invoice three weeks later.
#
# Whole dollars per month rather than an hourly rate times 730, to stay
# identical to the Bicep tree. ARM's mul and div only accept integers, so the
# Bicep side cannot do float arithmetic at all, and two trees reporting costs
# that differ by a couple of dollars would be a wart worth avoiding.
locals {
  monthly = {
    firewall = var.deploy_firewall ? lookup({
      Basic    = 288
      Standard = 912
      Premium  = 1278
    }, var.firewall_sku_tier, 912) : 0

    vpn_gateway          = var.deploy_vpn_gateway ? 139 : 0
    expressroute_gateway = var.deploy_expressroute_gateway ? 139 : 0
    bastion              = var.deploy_bastion ? 212 : 0
    route_server         = var.deploy_route_server ? 73 : 0

    # One Standard static public IP per appliance, about 4 per month each.
    public_ips = 4 * length(compact([
      var.deploy_firewall ? "fw" : "",
      var.deploy_vpn_gateway ? "vpn" : "",
      var.deploy_expressroute_gateway ? "er" : "",
      var.deploy_bastion ? "bas" : "",
      var.deploy_route_server ? "rs" : "",
    ]))
  }

  monthly_total = sum(values(local.monthly))
}

output "standing_monthly_cost_usd" {
  description = "Approximate standing cost in USD per month of whatever is switched on, retail West US 2, before data processing. Zero means only the free layer is deployed: virtual networks, subnets, peerings, network security groups and route tables bill nothing at rest."
  value = {
    monthly   = local.monthly_total
    breakdown = { for k, v in local.monthly : k => v if v > 0 }
    note      = local.monthly_total == 0 ? "Free layer only. Nothing here bills by the hour." : "Billable devices are running. Destroy them when you are done."
  }
}
