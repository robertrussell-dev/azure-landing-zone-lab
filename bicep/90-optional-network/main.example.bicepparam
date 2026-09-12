// Copy to main.bicepparam and fill in. main.bicepparam is gitignored.
//
// The connectivity subscription is the deployment scope, not a parameter, so it
// is passed as --subscription on the command line. See main.bicep.
using 'main.bicep'

param location = 'westus2'
param hubAddressSpace = '10.0.0.0/20'

// ---------------------------------------------------------------------------
// Everything below bills by the hour. All default to false.
// ---------------------------------------------------------------------------
// Approximate standing cost, retail West US 2 USD, before data processing:
//
//   deployFirewall             Standard  about 912 per month   (Basic: 288)
//   deployBastion              Standard  about 212 per month
//   deployVpnGateway           VpnGw1    about 139 per month
//   deployExpressRouteGateway  Standard  about 139 per month
//   deployRouteServer                    about  73 per month
//
// All five plus their public IPs is roughly 1,490 per month. Turn one on, get
// what you needed, turn it off the same day.

param deployFirewall = false
param firewallSkuTier = 'Standard'
param deployBastion = false
param deployVpnGateway = false
param deployExpressRouteGateway = false
param deployRouteServer = false
