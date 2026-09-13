// Management group hierarchy, the Bicep counterpart of
// terraform/00-management-groups.
//
// A management group deployment at the tenant root group, with scope: tenant()
// on every group, so it doesn't need a role at "/". bicep/README.md explains.
//
//   az deployment mg create --management-group-id <tenantId> \
//     --location westus2 --template-file main.bicep \
//     --parameters main.bicepparam

targetScope = 'managementGroup'

@description('Short lowercase prefix for management group names. Becomes part of every management group ID, which is immutable after creation.')
@minLength(2)
@maxLength(10)
param prefix string

@description('Display name of the intermediate root management group. Unlike the name, this can be changed later.')
param intermediateRootDisplayName string

// ---------------------------------------------------------------------------
// Intermediate root
// ---------------------------------------------------------------------------
// Everything hangs off this, so subscriptions can be moved in and the tree
// reorganized without touching the tenant root group.
//
// The parent is explicit. Omitting it also lands under the tenant root, but
// what-if reads the omission as removing the parent. The tenant root management
// group's ID is the tenant ID.
resource intermediateRoot 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: prefix
  properties: {
    displayName: intermediateRootDisplayName
    details: {
      parent: {
        id: tenantResourceId('Microsoft.Management/managementGroups', tenant().tenantId)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tier 1: the four top level groups
// ---------------------------------------------------------------------------
// Written as explicit resources rather than a loop. There are only four, they
// are not interchangeable, and each one exists for a different reason.

// Platform holds the subscriptions that serve every other landing zone.
resource platform 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${prefix}-platform'
  properties: {
    displayName: 'Platform'
    details: {
      parent: {
        id: intermediateRoot.id
      }
    }
  }
}

// Landing zones holds workload subscriptions, grouped by archetype.
resource landingZones 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${prefix}-landingzones'
  properties: {
    displayName: 'Landing zones'
    details: {
      parent: {
        id: intermediateRoot.id
      }
    }
  }
}

// Sandboxes are for experimentation, isolated from the hub, with permissive
// policy.
resource sandboxes 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${prefix}-sandboxes'
  properties: {
    displayName: 'Sandboxes'
    details: {
      parent: {
        id: intermediateRoot.id
      }
    }
  }
}

// Decommissioned holds canceled subscriptions, locked down by policy until their
// retention window ends.
resource decommissioned 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${prefix}-decommissioned'
  properties: {
    displayName: 'Decommissioned'
    details: {
      parent: {
        id: intermediateRoot.id
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tier 2: platform children
// ---------------------------------------------------------------------------
// Groups, not subscriptions placed directly under Platform, so a second
// connectivity subscription can be added later without reassigning policy.
//
// These four are identical in shape, so they're a loop. Position doesn't
// matter; ARM addresses each group by name.
var platformChildren = [
  {
    key: 'identity'
    displayName: 'Identity'
  }
  {
    key: 'management'
    displayName: 'Management'
  }
  {
    key: 'connectivity'
    displayName: 'Connectivity'
  }
  {
    key: 'security'
    displayName: 'Security'
  }
]

// Workload archetypes, not environments and not business units.
//
//   corp   requires hybrid connectivity routed through the hub
//   online does not require corporate connectivity
//   local  is for Azure Local clusters
//
// Environments (dev, test, prod) are subscriptions inside these groups, not
// management groups of their own. See ADR 0002.
var landingZoneArchetypes = [
  {
    key: 'corp'
    displayName: 'Corp'
  }
  {
    key: 'online'
    displayName: 'Online'
  }
  {
    key: 'local'
    displayName: 'Local'
  }
]

resource platformChild 'Microsoft.Management/managementGroups@2023-04-01' = [
  for child in platformChildren: {
    scope: tenant()
    name: '${prefix}-platform-${child.key}'
    properties: {
      displayName: child.displayName
      details: {
        parent: {
          id: platform.id
        }
      }
    }
  }
]

// ---------------------------------------------------------------------------
// Tier 2: landing zone archetypes
// ---------------------------------------------------------------------------
resource landingZoneArchetype 'Microsoft.Management/managementGroups@2023-04-01' = [
  for archetype in landingZoneArchetypes: {
    scope: tenant()
    name: '${prefix}-lz-${archetype.key}'
    properties: {
      displayName: archetype.displayName
      details: {
        parent: {
          id: landingZones.id
        }
      }
    }
  }
]

// ---------------------------------------------------------------------------
// Brownfield adoption target
// ---------------------------------------------------------------------------
// A copy of Corp with the same policy assignments set to DoNotEnforce. Adopted
// subscriptions start here and move to Corp once compliant. See ADR 0005.
resource landingZoneCorpAudit 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${prefix}-lz-corp-audit'
  properties: {
    displayName: 'Corp (audit only)'
    details: {
      parent: {
        id: landingZones.id
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tenant wide settings on the tenant root group
// ---------------------------------------------------------------------------
// Both belong on the tenant root group, which is why this file deploys there.

// Named from the tenant ID, so the settings can only land on the tenant root.
resource tenantRootGroup 'Microsoft.Management/managementGroups@2023-04-01' existing = {
  scope: tenant()
  name: tenant().tenantId
}

// New subscriptions land in Sandboxes, the least trusted placement, until
// someone places them. Creating management groups needs write access on the
// tenant root group; by default any user can.
resource hierarchySettings 'Microsoft.Management/managementGroups/settings@2023-04-01' = {
  parent: tenantRootGroup
  name: 'default'
  properties: {
    // The name, not the resource ID. The API stores and returns the name.
    defaultManagementGroup: sandboxes.name
    requireAuthorizationForGroupCreation: true
  }
}

// Enough to manage the groups and nothing else, as an alternative to
// Contributor at "/". Defined, not assigned or tested. The ID matches the
// Terraform tree.
resource hierarchyDeployer 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: '9eeae106-cb05-4621-8e59-1f2bea524ec3'
  properties: {
    roleName: '${prefix} hierarchy deployer'
    description: 'Create, move and delete management groups under the tenant root group, and run the deployments that do it. Nothing else.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Management/managementGroups/read'
          'Microsoft.Management/managementGroups/write'
          'Microsoft.Management/managementGroups/delete'
          'Microsoft.Resources/deployments/*'
        ]
      }
    ]
    assignableScopes: [
      managementGroup().id
    ]
  }
}

@description('Resource ID of the intermediate root management group.')
output intermediateRootId string = intermediateRoot.id

// Built with tenantResourceId, because a resource loop has no keyed collection
// to project.
@description('Every management group in the hierarchy, keyed by short name.')
output managementGroupIds object = union(
  {
    intermediate_root: intermediateRoot.id
    platform: platform.id
    landingzones: landingZones.id
    sandboxes: sandboxes.id
    decommissioned: decommissioned.id
    'lz-corp-audit': landingZoneCorpAudit.id
  },
  toObject(
    platformChildren,
    child => 'platform-${child.key}',
    child => tenantResourceId('Microsoft.Management/managementGroups', '${prefix}-platform-${child.key}')
  ),
  toObject(
    landingZoneArchetypes,
    archetype => 'lz-${archetype.key}',
    archetype => tenantResourceId('Microsoft.Management/managementGroups', '${prefix}-lz-${archetype.key}')
  )
)

// Bicep can't pin a tenant the way the azurerm provider does, so what-if shows
// this instead. Check it before the first deployment.
@description('Tenant the deployment ran against. Compare with az account show --query tenantId before applying.')
output deployedToTenantId string = tenant().tenantId
