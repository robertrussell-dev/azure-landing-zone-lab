// Resources that break the policy set, so the audit only assignment from ADR
// 0005 has something to report. A real adoption would already have these.
// All free.
//
// Always pass --subscription, since nothing in the file pins it:
//
//   az deployment sub create --subscription <brownfield GUID> \
//     --location westus2 --template-file main.bicep \
//     --parameters main.bicepparam

targetScope = 'subscription'

@description('Region for the seeded resources.')
param location string = 'westus2'

// ---------------------------------------------------------------------------
// Who owns the costCenter tag
// ---------------------------------------------------------------------------
// A redeploy strips the costCenter tag the Modify assignment added, until the
// next evaluation. Bicep has no ignore_changes; see bicep/README.md.

resource seed 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-legacy-app'
  location: location

  // No costCenter, so the Modify assignment has something to add.
  tags: {
    autoDelete: 'true'
  }
}

module network 'seed-network.bicep' = {
  scope: seed
  name: 'seed-network'
  params: {
    location: location
  }
}

@description('Resource ID of the subnet that has no network security group, which is the violation this directory exists to create.')
output nonCompliantSubnetId string = network.outputs.subnetId
