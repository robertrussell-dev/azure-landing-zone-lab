// Hub and spoke network, from the worked address plan in docs/ip-plan.md.
//
// The Bicep counterpart of terraform/90-optional-network. Same address plan,
// same archetype enforcement, same split between what is free and what bills.
//
// Two layers:
//
//   Free      hub and spoke virtual networks, every subnet the plan calls for,
//             peerings, network security groups, route tables. None of this
//             carries an hourly charge, so it can stay deployed.
//   Billable  firewall, gateways, Bastion, Route Server. All off by default.
//             Each flag names its own monthly cost below.
//
// ADR 0004 chose hub and spoke over Virtual WAN precisely because the free
// layer really is free. A Virtual WAN hub bills for existing; a virtual network
// and a peering do not.
//
// Scope. The connectivity subscription, which is where the platform owns the
// hub and the private DNS zones (ADR 0006):
//
//   az deployment sub create --subscription <connectivity GUID> \
//     --location westus2 --template-file main.bicep \
//     --parameters main.bicepparam

targetScope = 'subscription'

@description('Region for the hub and the spokes.')
param location string = 'westus2'

@description('The hub prefix. A /20 out of the platform /16, per docs/ip-plan.md. The subnet layout is derived from it.')
param hubAddressSpace string = '10.0.0.0/20'

@description('The spokes to build. One /22 per workload per environment, allocated sequentially. archetype decides routing and gateway transit, which is the real enforcement rather than the name.')
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

@description('The whole prefix belonging to each archetype. Routes are written against these rather than against individual spokes, which is why Corp and Online were split by address block instead of by naming convention. One route covers 64 spokes.')
param archetypeSupernets object = {
  corp: '10.1.0.0/16'
  online: '10.2.0.0/16'
}

// ---------------------------------------------------------------------------
// The flags. Everything above this line is free to leave running.
// ---------------------------------------------------------------------------
// Retail prices, West US 2, USD, checked against the Azure retail prices API on
// 2026-09-12. They matched ADR 0004's figures from 2026-09-06 exactly, so they
// are not moving quickly, but verify before trusting them.

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

@description('Who gets told if this subscription\'s spend crosses a threshold. A budget does not cap anything, but leaving a gateway running is exactly the mistake it exists to catch. Empty skips the budget.')
param budgetAlertEmails array = []

@description('Monthly budget for the connectivity subscription, in the billing account currency.')
@minValue(1)
param monthlyBudgetAmount int = 50

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
    tags: {
      autoDelete: 'true'
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
      // Gateway transit is the archetype. Corp reaches on premises through the
      // hub gateway, Online was never given the transit and so cannot. Azure
      // rejects the peering outright if this is true and no gateway exists, so
      // it is gated on the flags too.
      useRemoteGateways: s.archetype == 'corp' && (deployVpnGateway || deployExpressRouteGateway)
      // Every archetype supernet except this spoke's own. One route per
      // archetype covers all 64 spokes that fit in it.
      peerPrefixes: map(filter(items(archetypeSupernets), entry => entry.key != s.archetype), entry => entry.value)
      tags: union(tags, {
        archetype: s.archetype
      })
    }
  }
]

// A budget on the subscription that holds all of this. Created whether or not
// anything billable is switched on, because the point of it is to catch the
// case where something was switched on and forgotten. The forecast alert fires
// before the money is gone, which for a gateway left running is the only alert
// that helps.
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

@description('Which spokes can reach on premises through the hub gateway and which cannot. ADR 0003 as the deployment implements it, rather than as the names suggest.')
output archetypeEnforcement array = [
  for s in spokes: {
    spoke: s.name
    archetype: s.archetype
    gatewayTransit: s.archetype == 'corp' && (deployVpnGateway || deployExpressRouteGateway)
    defaultRouteToFirewall: s.archetype == 'corp' && deployFirewall
  }
]

// What this currently costs to leave running. Retail West US 2, USD, before any
// data processing. Surfaced as an output so the number shows in a what-if
// rather than on an invoice three weeks later.
//
// Whole dollars per month, not an hourly rate times 730. ARM's mul and div only
// accept integers, so float arithmetic here compiles fine and then fails at
// deployment with "expects its first parameter to be of type Integer". These
// figures are approximations anyway, which is what makes the integers honest
// rather than a workaround.
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
