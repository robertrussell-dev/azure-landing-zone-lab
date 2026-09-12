// The virtual network and the subnet that breaks the policy set.
//
// A separate file because main.bicep is a subscription deployment and these are
// resource group level resources. See the comment at the top of main.bicep for
// why any of this exists.

@description('Region for the seeded resources.')
param location string

// Violation 1: a subnet with no network security group attached.
//
// Trips "Subnets should be associated with a Network Security Group", assigned
// as AuditIfNotExists at the intermediate root. Reports, never blocks, so this
// is non compliant everywhere in the hierarchy rather than only under the audit
// only archetype.
//
// The subnet is declared inline rather than as a separate
// Microsoft.Network/virtualNetworks/subnets resource. Both work, and mixing
// them does not: a child subnet resource and an inline subnets array on the
// same virtual network overwrite each other on alternating deployments. Inline
// is the safe default when one file owns the whole network.
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

          // Set explicitly because the default moves with the API version.
          // Older versions default it to true, 2025-09-01 defaults it to
          // false, and Azure is retiring default outbound access entirely.
          // Inheriting a default that changes underneath you is how a subnet
          // silently loses internet egress on an unrelated version bump. There
          // is nothing in this subnet that needs egress.
          //
          // The Terraform tree has true here, inherited from the provider's
          // older API version rather than chosen. That is the disagreement
          // this line settles.
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
