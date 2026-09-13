// Everything in this file bills by the hour. All off by default; each flag's
// price is in main.bicep, and standingMonthlyCostUsd totals what's on. The
// deleteAfter tag from main.bicep lets bicep/30-auto-delete remove forgotten
// devices.

@description('Region.')
param location string

@description('Name of the hub virtual network these attach to.')
param hubVirtualNetworkName string

@description('Azure Firewall.')
param deployFirewall bool = false

@description('Firewall SKU tier.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param firewallSkuTier string = 'Standard'

@description('VPN gateway, VpnGw1.')
param deployVpnGateway bool = false

@description('ExpressRoute gateway, Standard. The gateway only; the circuit is a carrier contract.')
param deployExpressRouteGateway bool = false

@description('Azure Bastion, Standard.')
param deployBastion bool = false

@description('Azure Route Server.')
param deployRouteServer bool = false

@description('Tags applied to every resource.')
param tags object = {}

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVirtualNetworkName
}

var subnetId = {
  firewall: '${hub.id}/subnets/AzureFirewallSubnet'
  gateway: '${hub.id}/subnets/GatewaySubnet'
  bastion: '${hub.id}/subnets/AzureBastionSubnet'
  routeServer: '${hub.id}/subnets/RouteServerSubnet'
}

// ---------------------------------------------------------------------------
// Azure Firewall
// ---------------------------------------------------------------------------
resource firewallPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployFirewall) {
  name: 'pip-fw-hub'
  location: location
  tags: tags
  // Azure Firewall requires Standard SKU and static allocation.
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = if (deployFirewall) {
  name: 'afwp-hub'
  location: location
  tags: tags
  properties: {
    sku: {
      tier: firewallSkuTier
    }
    // Deny rather than the Alert default. With a policy attached the firewall
    // inherits threat intelligence settings from it, so this is the only place
    // the setting has any effect.
    threatIntelMode: 'Deny'
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = if (deployFirewall) {
  name: 'afw-hub'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: firewallSkuTier
    }
    // Also set on the policy, which is what takes effect. Kept here for
    // readers and scanners; ARM accepts both.
    threatIntelMode: 'Deny'
    firewallPolicy: {
      id: deployFirewall ? firewallPolicy.id : null
    }
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          subnet: {
            id: subnetId.firewall
          }
          publicIPAddress: {
            id: deployFirewall ? firewallPip.id : null
          }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// VPN gateway
// ---------------------------------------------------------------------------
// 30 to 45 minutes to create, and the same to destroy.
resource vpnPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployVpnGateway) {
  name: 'pip-vgw-hub'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = if (deployVpnGateway) {
  name: 'vgw-hub'
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: {
      name: 'VpnGw1'
      tier: 'VpnGw1'
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          subnet: {
            id: subnetId.gateway
          }
          publicIPAddress: {
            id: deployVpnGateway ? vpnPip.id : null
          }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// ExpressRoute gateway
// ---------------------------------------------------------------------------
// The gateway only; the circuit is a carrier contract. It shares GatewaySubnet
// with the VPN gateway, which is why that subnet is a /26.
resource erPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployExpressRouteGateway) {
  name: 'pip-ergw-hub'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource expressRouteGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = if (deployExpressRouteGateway) {
  name: 'ergw-hub'
  location: location
  tags: tags
  properties: {
    gatewayType: 'ExpressRoute'
    sku: {
      name: 'Standard'
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          subnet: {
            id: subnetId.gateway
          }
          // Still required, even though no traffic reaches it over the internet.
          publicIPAddress: {
            id: deployExpressRouteGateway ? erPip.id : null
          }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Azure Bastion
// ---------------------------------------------------------------------------
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployBastion) {
  name: 'pip-bas-hub'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = if (deployBastion) {
  name: 'bas-hub'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'configuration'
        properties: {
          subnet: {
            id: subnetId.bastion
          }
          publicIPAddress: {
            id: deployBastion ? bastionPip.id : null
          }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Azure Route Server
// ---------------------------------------------------------------------------
// A virtual hub with an ipConfiguration child in ARM. Only useful with a BGP
// speaking appliance peering with it, which this lab doesn't have.
resource routeServerPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployRouteServer) {
  name: 'pip-rs-hub'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource routeServer 'Microsoft.Network/virtualHubs@2024-05-01' = if (deployRouteServer) {
  name: 'rs-hub'
  location: location
  tags: tags
  properties: {
    sku: 'Standard'
    allowBranchToBranchTraffic: false
  }
}

resource routeServerIpConfig 'Microsoft.Network/virtualHubs/ipConfigurations@2024-05-01' = if (deployRouteServer) {
  parent: routeServer
  name: 'ipconfig1'
  properties: {
    subnet: {
      id: subnetId.routeServer
    }
    publicIPAddress: {
      id: deployRouteServer ? routeServerPip.id : null
    }
  }
}

@description('Private IP of the firewall, or an empty string when no firewall is deployed. The spokes route to this.')
// The ternary already guards this, but Bicep cannot narrow a conditional
// resource through one, so the non-null assertion says so explicitly.
output firewallPrivateIp string = deployFirewall
  ? firewall!.properties.ipConfigurations[0].properties.privateIPAddress
  : ''
