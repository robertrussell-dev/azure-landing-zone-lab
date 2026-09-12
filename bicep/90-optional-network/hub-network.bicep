// The hub virtual network and every subnet in docs/ip-plan.md.
//
// Every prefix is derived from hubAddressSpace rather than typed, which is what
// proves the plan is systematic rather than numbers that happen not to collide.
// Everything in this file is free to leave running.
//
// Five of the subnet names are mandatory and case sensitive: Azure will not
// attach the service to a subnet spelled any other way.

@description('Region for the hub.')
param location string

@description('The hub prefix. A /20 out of the platform /16. Every subnet below is derived from it.')
param hubAddressSpace string

@description('ID of the policy assignment that audits subnets without a network security group. Empty skips the exemptions.')
param subnetNsgPolicyAssignmentId string = ''

@description('Tags applied to every resource.')
param tags object = {}

// The first four /26s tile the first /24 of the hub exactly. RouteServerSubnet
// is also a /26, not the /27 some older material shows: a /27 fails at create
// time. The DNS resolver endpoints start after it, at 10.0.1.64.
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

// The baseline network security group goes on the four subnets that can safely
// carry one: the two general purpose ones and both DNS resolver endpoints
// (delegation does not prevent it). The other five cannot. AzureFirewallSubnet,
// AzureFirewallManagementSubnet and RouteServerSubnet do not support one.
// AzureBastionSubnet needs a specific rule set that is meaningless until Bastion
// exists, and GatewaySubnet accepts one but Microsoft advises against it,
// because a wrong rule breaks the control plane. Each of the five carries a
// policy exemption, below.
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

// ---------------------------------------------------------------------------
// Policy exemptions
// ---------------------------------------------------------------------------
// The audit assignment at the intermediate root flags every subnet without a
// network security group, and the built in definition makes no exception for
// the platform subnets above. An exemption records the decision where the
// compliance report shows it, rather than leaving five permanent findings.
//
// Mitigated, not Waiver: the risk the audit looks for is handled by the service
// that owns each subnet, so this is not a temporary allowance.
var subnetsWithoutNsg = [
  'GatewaySubnet'
  'AzureFirewallSubnet'
  'AzureFirewallManagementSubnet'
  'AzureBastionSubnet'
  'RouteServerSubnet'
]

resource subnetWithoutNsg 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = [
  for subnetName in subnetsWithoutNsg: {
    parent: hub
    name: subnetName
  }
]

resource hubNoNsgExemption 'Microsoft.Authorization/policyExemptions@2022-07-01-preview' = [
  for (subnetName, i) in subnetsWithoutNsg: if (!empty(subnetNsgPolicyAssignmentId)) {
    scope: subnetWithoutNsg[i]
    name: 'exempt-nsg-${toLower(subnetName)}'
    properties: {
      displayName: '${subnetName} cannot carry the baseline network security group'
      description: 'Azure either rejects a network security group on this subnet or advises against one, and the service that owns it provides its own protection.'
      policyAssignmentId: subnetNsgPolicyAssignmentId
      exemptionCategory: 'Mitigated'
    }
  }
]

@description('Resource ID of the hub virtual network.')
output virtualNetworkId string = hub.id

@description('Name of the hub virtual network.')
output virtualNetworkName string = hub.name

@description('The hub subnet layout as actually derived, so it can be diffed against docs/ip-plan.md.')
output subnetPrefixes object = subnetPrefixes
