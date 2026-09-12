// Deliberately non compliant resources, created on purpose.
//
// ADR 0005's audit only adoption only shows anything if the adopted subscription
// actually breaks the policies it is measured against. An empty subscription
// reports no compliance state at all. In a real engagement the violations
// already exist; here they are seeded. Everything below is free.
//
// Scope. The brownfield subscription, and only that one. Type --subscription
// rather than relying on whatever az account show returns; it does the job the
// aliased provider does in the Terraform version:
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
// The Modify assignment at the intermediate root appends costCenter. A redeploy
// here overwrites the tags below and strips it until the policy's next
// evaluation, and Bicep has no ignore_changes to settle that with. See "The
// Modify policy fight is silent instead of loud" in bicep/README.md.

resource seed 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-legacy-app'
  location: location

  // Deliberately missing costCenter. The Modify assignment at the intermediate
  // root appends it to resources that lack it, so this is also the test of
  // whether that assignment does what it claims.
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
