// One spoke virtual network, its subnets, its route table and both halves of
// the peering with the hub.
//
// The Bicep counterpart of terraform/modules/spoke-network. Everything here is
// free to leave running: virtual networks, subnets, peerings, network security
// groups and route tables carry no hourly charge, which is the reason ADR 0004
// chose hub and spoke over Virtual WAN for a lab on a personal card.
//
// Subnets are derived from the spoke's own prefix rather than listed, so a
// spoke cannot be handed a subnet outside its allocation. cidrSubnet does the
// same arithmetic Terraform's cidrsubnet does, and the two produce identical
// prefixes.

@description('Short spoke name, for example corp-payments-prod. Used in every resource name.')
param name string

@description('Region for the spoke.')
param location string

@description('The spoke\'s whole prefix. One /22 per workload per environment.')
param addressSpace string

@description('corp or online. Not a label: corp gets a default route to the firewall and gateway transit to on premises, online gets neither, and that is what enforces the archetype. See ADR 0003.')
@allowed([
  'corp'
  'online'
])
param archetype string

@description('Name of the hub virtual network to peer with. Assumed to be in this resource group.')
param hubVirtualNetworkName string

@description('Private IP of the hub firewall. Empty when no firewall is deployed, which leaves the route table in place and empty rather than pointing traffic at a next hop that does not exist.')
param firewallPrivateIp string = ''

@description('Whether this spoke routes to on premises through the hub gateway. Azure rejects the peering if this is true and the hub has no gateway, so the caller ties it to whether one was actually deployed.')
param useRemoteGateways bool = false

@description('Prefixes belonging to other archetypes, routed to the firewall so spoke to spoke traffic is inspected. Peering is not transitive, so without these the spokes cannot reach each other at all.')
param peerPrefixes array = []

@description('Tags applied to every resource in the spoke.')
param tags object = {}

// A /22 splits into four /24s. Three are used and the fourth is carved
// further, which matches the worked plan exactly.
var subnetPrefixes = {
  app: cidrSubnet(addressSpace, 24, 0)
  data: cidrSubnet(addressSpace, 24, 1)
  privateendpoints: cidrSubnet(addressSpace, 24, 2)
  appgw: cidrSubnet(addressSpace, 26, 12)
}

// 0.0.0.0/0 to the firewall is forced tunnelling and applies to corp only. An
// online spoke reaching the internet directly is the point of the archetype.
var wantDefaultRoute = archetype == 'corp' && !empty(firewallPrivateIp)

var defaultRoute = wantDefaultRoute
  ? [
      {
        name: 'to-firewall-default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  : []

// Cross archetype routes apply to both, because the firewall is the only path
// between spokes either way.
// map rather than a for-expression, because Bicep does not allow a
// for-expression inside a ternary (BCP138) and the routes only exist when
// there is a firewall to point them at.
var peerRoutes = empty(firewallPrivateIp)
  ? []
  : map(peerPrefixes, prefix => {
      name: 'to-firewall-${replace(replace(prefix, '.', '-'), '/', '-')}'
      properties: {
        addressPrefix: prefix
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: firewallPrivateIp
      }
    })

// Deliberately empty of custom rules. Azure's defaults already deny inbound
// from the internet and permit traffic inside the virtual network, so an empty
// group is a working baseline rather than a placeholder. It mainly exists so
// every subnet that can carry one does, which is what the AuditIfNotExists
// assignment at the intermediate root looks for.
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${name}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// Created whether or not a firewall exists, so switching the firewall on later
// adds routes rather than restructuring anything.
resource routeTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-${name}'
  location: location
  tags: tags
  properties: {
    routes: concat(defaultRoute, peerRoutes)
    disableBgpRoutePropagation: false
  }
}

resource spoke 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${name}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    // Subnets inline, never as child resources. Mixing the two makes
    // alternating deployments overwrite each other, which Microsoft documents.
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefixes: [
            subnetPrefixes.app
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: routeTable.id
          }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefixes: [
            subnetPrefixes.data
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: routeTable.id
          }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-privateendpoints'
        properties: {
          addressPrefixes: [
            subnetPrefixes.privateendpoints
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: routeTable.id
          }
          defaultOutboundAccess: false
        }
      }
      {
        // No network security group and no route table, both on purpose.
        // Application Gateway v2 needs inbound 65200-65535 from GatewayManager
        // to stay manageable, and a default route to a firewall breaks its
        // control plane. Those rules belong with an actual gateway deployment.
        // The subnet is reserved and empty until then.
        name: 'snet-appgw'
        properties: {
          addressPrefixes: [
            subnetPrefixes.appgw
          ]
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVirtualNetworkName
}

// Peering is not transitive and it is not symmetrical to configure. Each side
// is its own resource and the flags mean different things at each end.
resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: spoke
  name: 'peer-${name}-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hub.id
    }
    allowVirtualNetworkAccess: true
    // Required for the hub firewall to forward traffic that did not originate
    // there, which is every spoke to spoke packet.
    allowForwardedTraffic: true
    // The archetype, expressed as a peering flag. Azure rejects this outright
    // if the hub has no gateway, so the caller only sets it when one exists.
    useRemoteGateways: useRemoteGateways
  }
}

resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: 'peer-hub-to-${name}'
  properties: {
    remoteVirtualNetwork: {
      id: spoke.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    // The hub offers its gateway. Whether a spoke takes it is decided on the
    // other side, by useRemoteGateways.
    allowGatewayTransit: true
  }
}

@description('Resource ID of the spoke virtual network.')
output virtualNetworkId string = spoke.id

@description('Name of the spoke virtual network.')
output virtualNetworkName string = spoke.name

@description('The derived subnet prefixes, so the address plan can be checked against the plan document without reading deployed state.')
output subnetPrefixes object = subnetPrefixes
