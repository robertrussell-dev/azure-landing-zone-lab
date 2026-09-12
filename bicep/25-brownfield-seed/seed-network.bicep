// The virtual network and the subnet that breaks the policy set.
//
// A separate file because main.bicep is a subscription deployment and these are
// resource group level resources. See the comment at the top of main.bicep for
// why any of this exists.

@description('Region for the seeded resources.')
param location string

// The violation: a subnet with no network security group. It trips the
// AuditIfNotExists assignment at the intermediate root, which reports and never
// blocks, so it is non compliant everywhere in the hierarchy.
//
// The subnet is inline rather than a separate subnets resource. Mixing the two
// on one virtual network makes them overwrite each other on alternate
// deployments, so inline is the safe default when one file owns the network.
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
          // Plural, not addressPrefix. Both are accepted and the API returns
          // the plural form, so declaring the singular makes every what-if
          // against an existing subnet report a change that isn't one. The
          // Terraform resource uses address_prefixes for the same reason.
          addressPrefixes: [
            '10.240.0.0/26'
          ]

          // Set explicitly because the default moves with the API version:
          // true on older versions, false on 2025-09-01. A default that
          // changes underneath you is how a subnet silently loses egress on an
          // unrelated version bump. The Terraform tree inherits true from the
          // provider's older API version.
          defaultOutboundAccess: false

          // No networkSecurityGroup property, on purpose. That absence is the
          // whole point of this file.
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
