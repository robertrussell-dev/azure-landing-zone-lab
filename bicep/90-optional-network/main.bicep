// Hub and spoke network, from the worked address plan in docs/ip-plan.md.
//
// The virtual networks, subnets, peerings, network security groups and route
// tables are free and stay deployed. The firewall, gateways, Bastion and Route
// Server bill hourly and are off by default, each behind a flag below.
//
// Deployed to the connectivity subscription:
//
//   az deployment sub create --subscription <connectivity GUID> \
//     --location westus2 --template-file main.bicep \
//     --parameters main.bicepparam

targetScope = 'subscription'

@description('Region for the hub and the spokes.')
param location string = 'westus2'

@description('Management group prefix used by bicep/00-management-groups. The exemptions name the subnet network security group assignment at the intermediate root, whose ID is built from it.')
@minLength(2)
@maxLength(10)
param prefix string

@description('The hub prefix. A /20 out of the platform /16, per docs/ip-plan.md. The subnet layout is derived from it.')
param hubAddressSpace string = '10.0.0.0/20'

@description('The spokes to build. One /22 per workload per environment, allocated sequentially. archetype decides routing and gateway transit.')
param spokes array = [
  {
    name: 'corp-payments-prod'
    addressSpace: '10.1.0.0/22'
    archetype: 'corp'
  }
  {
    name: 'online-portal-prod'
    addressSpace: '10.2.0.0/22'
    archetype: 'online'
  }
]

@description('The whole prefix belonging to each archetype. Routes target these blocks instead of individual spokes, which is why Corp and Online have separate address blocks. One route covers 64 spokes.')
param archetypeSupernets object = {
  corp: '10.1.0.0/16'
  online: '10.2.0.0/16'
}

// ---------------------------------------------------------------------------
// The flags. Everything above this line is free to leave running.
// ---------------------------------------------------------------------------
// Retail prices, West US 2, USD, from the retail prices API on 2026-09-12.

@description('Azure Firewall in the hub. Standard: 1.25 per hour, about 912 per month, plus 0.016 per GB processed. The single most expensive thing in this repository. Nothing routes through the hub without it, so the spoke route tables stay empty while this is false.')
param deployFirewall bool = false

@description('Basic is 0.395 per hour, about 288 per month, and is enough to demonstrate the topology.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param firewallSkuTier string = 'Standard'

@description('VPN gateway in the hub. VpnGw1: 0.19 per hour, about 139 per month. Takes 30 to 45 minutes to create and about as long to destroy, which matters more than the money when taking it down the same day.')
param deployVpnGateway bool = false

@description('ExpressRoute gateway in the hub. Standard: 0.19 per hour, about 139 per month, and that is only the gateway. The circuit is a separate carrier contract and is not created here.')
param deployExpressRouteGateway bool = false

@description('Azure Bastion in the hub. Standard: 0.29 per hour, about 212 per month.')
param deployBastion bool = false

@description('Azure Route Server in the hub. About 0.10 per hour per routing unit, roughly 73 per month at minimum capacity. Only useful with a BGP speaking network virtual appliance, and there is not one here.')
param deployRouteServer bool = false

@description('How long a billable device may exist before the janitor in bicep/30-auto-delete deletes it. Stamped on each device as its deleteAfter tag.')
@minValue(1)
@maxValue(72)
param billableTtlHours int = 8

// Start of the deleteAfter window. A parameter because utcNow only works as a
// default. Unlike Terraform, every deployment restamps the tag; see
// bicep/README.md.
@description('Deployment time. Leave unset.')
param deployedAt string = utcNow('u')

@description('Who gets told if this subscription\'s spend crosses a threshold. A budget does not cap anything, but leaving a gateway running is exactly the mistake it exists to catch. Empty skips the budget.')
param budgetAlertEmails array = []

@description('Monthly budget for the connectivity subscription, in the billing account currency.')
@minValue(1)
param monthlyBudgetAmount int = 50

// The assignment that audits subnets without a network security group. The hub
// and each spoke exempt the subnets that must stay without one.
var subnetNsgAssignmentId = extensionResourceId(
  tenantResourceId('Microsoft.Management/managementGroups', prefix),
  'Microsoft.Authorization/policyAssignments',
  'audit-subnet-nsg'
)

var tags = {
  autoDelete: 'false'
}

resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-hub-network'
  location: location
  tags: tags
}

module hubNetwork 'hub-network.bicep' = {
  scope: hubResourceGroup
  name: 'hub-network'
  params: {
    location: location
    hubAddressSpace: hubAddressSpace
    subnetNsgPolicyAssignmentId: subnetNsgAssignmentId
    tags: tags
  }
}

// The appliances go in before the spokes, because the spokes need the
// firewall's private IP to write their routes and an empty string is a
// perfectly good answer when there is no firewall.
module billable 'billable.bicep' = {
  scope: hubResourceGroup
  name: 'billable-devices'
  params: {
    location: location
    hubVirtualNetworkName: hubNetwork.outputs.virtualNetworkName
    deployFirewall: deployFirewall
    firewallSkuTier: firewallSkuTier
    deployVpnGateway: deployVpnGateway
    deployExpressRouteGateway: deployExpressRouteGateway
    deployBastion: deployBastion
    deployRouteServer: deployRouteServer
    // Both tags are what the janitor in bicep/30-auto-delete looks for.
    // Formatted to match the RFC 3339 value Terraform's timeadd produces.
    tags: {
      autoDelete: 'true'
      deleteAfter: dateTimeAdd(deployedAt, 'PT${billableTtlHours}H', 'yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
    }
  }
}

module spoke '../modules/spoke-network/main.bicep' = [
  for s in spokes: {
    scope: hubResourceGroup
    name: 'spoke-${s.name}'
    params: {
      name: s.name
      location: location
      addressSpace: s.addressSpace
      archetype: s.archetype
      hubVirtualNetworkName: hubNetwork.outputs.virtualNetworkName
      firewallPrivateIp: billable.outputs.firewallPrivateIp
      // Corp reaches on premises through the hub gateway; Online can't. Azure
      // rejects the peering if there's no gateway, so it's gated on the flags.
      useRemoteGateways: s.archetype == 'corp' && (deployVpnGateway || deployExpressRouteGateway)
      // Every archetype supernet except this spoke's own. One route per
      // archetype covers all 64 spokes that fit in it.
      peerPrefixes: map(filter(items(archetypeSupernets), entry => entry.key != s.archetype), entry => entry.value)
      subnetNsgPolicyAssignmentId: subnetNsgAssignmentId
      tags: union(tags, {
        archetype: s.archetype
      })
    }
  }
]

// A budget on this subscription. Always created, since its job is catching a
// device someone forgot.
module budget '../modules/subscription-budget/main.bicep' = if (!empty(budgetAlertEmails)) {
  name: 'budget-connectivity'
  params: {
    name: 'budget-connectivity'
    amount: monthlyBudgetAmount
    contactEmails: budgetAlertEmails
    actualThresholdPercent: 50
    forecastThresholdPercent: 80
  }
}

@description('The hub subnet layout as actually derived, so it can be diffed against docs/ip-plan.md.')
output hubSubnetPrefixes object = hubNetwork.outputs.subnetPrefixes

@description('Every spoke\'s derived subnets, same purpose.')
output spokeSubnetPrefixes array = [for (s, i) in spokes: spoke[i].outputs.subnetPrefixes]

@description('Which spokes can reach on premises through the hub gateway and which cannot. ADR 0003 as deployed.')
output archetypeEnforcement array = [
  for s in spokes: {
    spoke: s.name
    archetype: s.archetype
    gatewayTransit: s.archetype == 'corp' && (deployVpnGateway || deployExpressRouteGateway)
    defaultRouteToFirewall: s.archetype == 'corp' && deployFirewall
  }
]

// Monthly cost of what's switched on, retail West US 2, USD, before data
// processing. Whole dollars, because ARM's mul and div only take integers:
// floats compile, then fail at deployment.
var firewallMonthly = deployFirewall
  ? (firewallSkuTier == 'Basic' ? 288 : (firewallSkuTier == 'Premium' ? 1278 : 912))
  : 0
var vpnMonthly = deployVpnGateway ? 139 : 0
var expressRouteMonthly = deployExpressRouteGateway ? 139 : 0
var bastionMonthly = deployBastion ? 212 : 0
var routeServerMonthly = deployRouteServer ? 73 : 0

// One Standard static public IP per appliance, about 4 per month each.
var publicIpCount = length(filter(
  [deployFirewall, deployVpnGateway, deployExpressRouteGateway, deployBastion, deployRouteServer],
  flag => flag
))
var publicIpMonthly = publicIpCount * 4

var monthlyTotal = firewallMonthly + vpnMonthly + expressRouteMonthly + bastionMonthly + routeServerMonthly + publicIpMonthly

@description('Approximate standing cost in USD per month of whatever is switched on, retail West US 2, before data processing. Zero means only the free layer is deployed.')
output standingMonthlyCostUsd object = {
  monthly: monthlyTotal
  breakdown: {
    firewall: firewallMonthly
    vpnGateway: vpnMonthly
    expressRouteGateway: expressRouteMonthly
    bastion: bastionMonthly
    routeServer: routeServerMonthly
    publicIps: publicIpMonthly
  }
  note: monthlyTotal == 0
    ? 'Free layer only. Nothing here bills by the hour.'
    : 'Billable devices are running. Destroy them when you are done.'
}
