// The virtual network and the noncompliant subnet. A separate file because
// main.bicep is subscription scoped.

@description('Region for the seeded resources.')
param location string

// The violation: a subnet with no network security group, reported by the
// AuditIfNotExists assignment.
resource seed 'Microsoft.Network/virtualNetworks@2025-09-01' = {
  name: 'vnet-legacy-app'
  location: location

  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.240.0.0/24'
      ]
    }

    subnets: [
      {
        name: 'snet-no-nsg'
        properties: {
          // Plural, because the API returns the plural and what-if diffs
          // the singular.
          addressPrefixes: [
            '10.240.0.0/26'
          ]

          // Explicit, because the default changed to false in 2025-09-01.
          // The Terraform tree gets true from an older API version.
          defaultOutboundAccess: false
        }
      }
    ]
  }

  tags: {
    autoDelete: 'true'
  }
}

@description('Resource ID of the subnet with no network security group.')
output subnetId string = seed.properties.subnets[0].id
