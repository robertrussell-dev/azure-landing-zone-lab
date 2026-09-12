// The hub virtual network, and every subnet the worked address plan calls for.
//
// The plan this implements is docs/ip-plan.md. Nothing here is invented: the
// prefixes, the subnet names and the sizes come from that document, and the
// derivations below are what prove the plan is systematic rather than a list of
// numbers that happen not to collide.
//
// Everything in this file is free. A virtual network with nine subnets costs
// nothing per hour, which is what makes it reasonable to leave the shape of the
// network deployed permanently and bring only the appliances up on demand.
//
// Four of these subnet names are mandatory and case sensitive. Azure will not
// attach the service if they are spelled anything else, and the failure is a
// deployment error rather than a warning.

@description('Region for the hub.')
param location string

@description('The hub prefix. A /20 out of the platform /16. Every subnet below is derived from it.')
param hubAddressSpace string

@description('Tags applied to every resource.')
param tags object = {}

// The four mandatory /26s tile the first /24 of the hub exactly. That is
// deliberate in the plan and survives here because every prefix is derived
// rather than typed.
//
// RouteServerSubnet is a /26, not the /27 that older material and one surviving
// Microsoft tutorial still show. A /27 fails at create time, and widening it to
// /26 is what pushed the DNS resolver endpoints from 10.0.1.32 and 10.0.1.48 up
// to 10.0.1.64 and 10.0.1.80.
var subnetPrefixes = {
  GatewaySubnet: cidrSubnet(hubAddressSpace, 26, 0)
  AzureFirewallSubnet: cidrSubnet(hubAddressSpace, 26, 1)
  AzureFirewallManagementSubnet: cidrSubnet(hubAddressSpace, 26, 2)
  AzureBastionSubnet: cidrSubnet(hubAddressSpace, 26, 3)
  RouteServerSubnet: cidrSubnet(hubAddressSpace, 26, 4)
  dnsInbound: cidrSubnet(hubAddressSpace, 28, 20)
  dnsOutbound: cidrSubnet(hubAddressSpace, 28, 21)
  sharedPrivateEndpoints: cidrSubnet(hubAddressSpace, 24, 2)
  sharedServices: cidrSubnet(hubAddressSpace, 24, 3)
}

// Four subnets get the baseline group: the two general purpose ones and both
// DNS resolver endpoints. Delegation does not prevent a subnet from carrying
// one.
//
// The other five do not, and cannot safely. AzureFirewallSubnet,
// AzureFirewallManagementSubnet and RouteServerSubnet do not support one at
// all. AzureBastionSubnet supports one only with a specific rule set that is
// meaningless until Bastion exists. GatewaySubnet accepts one and Microsoft
// advises against it, because the wrong rule breaks the control plane. So the
// subnets left without one are left that way on purpose, and the audit
// assignment at the intermediate root will report them.
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-hub-shared'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-hub'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressSpace
      ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefixes: [
            subnetPrefixes.GatewaySubnet
          ]
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefixes: [
            subnetPrefixes.AzureFirewallSubnet
          ]
        }
      }
      {
        name: 'AzureFirewallManagementSubnet'
        properties: {
          addressPrefixes: [
            subnetPrefixes.AzureFirewallManagementSubnet
          ]
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefixes: [
            subnetPrefixes.AzureBastionSubnet
          ]
        }
      }
      {
        name: 'RouteServerSubnet'
        properties: {
          addressPrefixes: [
            subnetPrefixes.RouteServerSubnet
          ]
        }
      }
      {
        // The DNS Private Resolver endpoints need delegated subnets and cannot
        // share them with anything else.
        name: 'snet-dns-inbound'
        properties: {
          addressPrefixes: [
            subnetPrefixes.dnsInbound
          ]
          delegations: [
            {
              name: 'dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'snet-dns-outbound'
        properties: {
          addressPrefixes: [
            subnetPrefixes.dnsOutbound
          ]
          delegations: [
            {
              name: 'dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'snet-shared-privateendpoints'
        properties: {
          addressPrefixes: [
            subnetPrefixes.sharedPrivateEndpoints
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-shared-services'
        properties: {
          addressPrefixes: [
            subnetPrefixes.sharedServices
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

@description('Resource ID of the hub virtual network.')
output virtualNetworkId string = hub.id

@description('Name of the hub virtual network.')
output virtualNetworkName string = hub.name

@description('The hub subnet layout as actually derived, so it can be diffed against docs/ip-plan.md.')
output subnetPrefixes object = subnetPrefixes
