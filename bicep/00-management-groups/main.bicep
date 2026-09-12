// Management group hierarchy, composed by hand.
//
// The Bicep counterpart of terraform/00-management-groups: same tree, same
// reasons. ALZ-Bicep would generate this and a great deal more; ADR 0007 records
// why it is not used.
//
// Scope. Management groups are tenant level resources, but this runs at the
// tenant root management group and creates each group with scope: tenant():
//
//   az deployment mg create --management-group-id <tenantId> \
//     --location westus2 --template-file main.bicep \
//     --parameters main.bicepparam
//
// The groups land in the same place either way. What changes is the access the
// operator needs. A tenant deployment needs a role at "/", which takes built in
// roles only, so the narrowest grant there is Contributor over the whole
// tenant. The tenant root management group accepts custom roles, so the grant
// can be limited to deployments and management groups. Microsoft documents this
// shape for principals that cannot deploy at the tenant:
// https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-management-group#management-group
//
// The cost is that every group below has to state scope: tenant() explicitly.
// 20-subscription-placement has no such option, because subscription aliases
// are tenant scoped.

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
// Everything hangs off this, not off the tenant root group directly. Building
// under an intermediate root is what allows existing subscriptions to be moved
// in, and the structure below to be reorganised, without ever touching the
// tenant root group.
//
// The parent is stated rather than left to the default. Omitting details.parent
// does place a new group under the tenant root, and that is what the Terraform
// version relies on, but it reads as an omission rather than a decision and it
// is not free: against the deployed hierarchy, what-if reports this as removing
// properties.details from the one group in the tree whose placement the ADRs
// argue about. Naming it costs a line and the diff goes away.
//
// The tenant root management group's ID is the tenant ID.
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
//
// Referencing intermediateRoot.id is also what orders the deployment. Bicep
// infers the dependency from the reference, so there is no dependsOn to keep in
// step with the tree.

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

// Sandboxes are deliberately loose. Subscriptions here are for experimentation
// and are isolated from the hub, so policy here is permissive by design rather
// than by neglect.
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

// Decommissioned holds subscriptions on their way out. Cancelled subscriptions
// are moved here so that policy can keep them locked down during the retention
// window before deletion becomes permanent.
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
// Each of these is a management group that will contain a subscription, not a
// subscription placed directly under Platform. Microsoft describes Connectivity
// as "dedicated subscriptions, commonly a single subscription for most
// organizations". The management group layer exists so a second connectivity
// subscription can be added later without restructuring the tree or reassigning
// policy.
//
// These four are structurally identical, so they are written as a loop. The
// array keeps the data separate from the resource shape.
//
// Bicep loops are positional where Terraform's for_each is keyed, but nothing
// here depends on position: ARM addresses a resource by its name, so reordering
// this array changes the order of deployment and nothing else.
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
// A duplicate of the Corp archetype carrying the same policy assignments with
// enforcementMode set to DoNotEnforce.
//
// Subscriptions being adopted from an existing estate are placed here first.
// They are evaluated against the policies they will eventually be held to,
// and nothing is blocked while that assessment happens. When compliance is
// acceptable the subscription moves to Corp, and enforcement begins without
// any policy being rewritten.
//
// This duplicates the hierarchy and the assignments. It does not duplicate any
// workload, so it costs nothing. See ADR 0005.
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
// Both belong on the tenant root group, so this file runs there rather than at
// any management group: the role is created at the deployment's own scope, and
// hierarchy settings only exist on the tenant root group. Both are free.

// Named from the tenant ID rather than the deployment scope, so the settings
// can only ever land on the tenant root group.
resource tenantRootGroup 'Microsoft.Management/managementGroups@2023-04-01' existing = {
  scope: tenant()
  name: tenant().tenantId
}

// Where a new subscription lands when nobody says otherwise, and who may create
// management groups. Sandboxes is the least trusted placement, so a
// subscription created outside vending starts with no route to on premises
// until someone decides where it belongs. Without
// requireAuthorizationForGroupCreation any user in the tenant can create
// management groups under the tenant root.
resource hierarchySettings 'Microsoft.Management/managementGroups/settings@2023-04-01' = {
  parent: tenantRootGroup
  name: 'default'
  properties: {
    // The name, not the resource ID. The API stores and returns the name.
    defaultManagementGroup: sandboxes.name
    requireAuthorizationForGroupCreation: true
  }
}

// A least privilege role for the hierarchy. The root scope "/" accepts built in
// roles only, so the narrowest grant there is Contributor over the whole tenant.
// The tenant root group accepts custom roles, so the narrow alternative can be
// a real role: enough to create, move and delete management groups and run the
// deployments that do it. It covers the groups, which is the part that changes
// over time; the hierarchy settings and the role itself are one off setup that
// needs broader access.
//
// Defined, not assigned. The action list covers what this file creates; it has
// not been exercised through an assignment. The ID matches the Terraform tree so
// both describe the same role.
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

// The looped groups are named rather than indexed here. A Bicep resource loop
// has no keyed collection to project, so reaching them by symbolic name would
// mean mapping over range(0, length(...)) and indexing back. tenantResourceId
// builds the same IDs from the same data with less ceremony.
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

// The tenant this actually deployed to.
//
// The azurerm provider pins tenant_id and subscription_id in configuration, so
// a stray "az account set" cannot send an apply to the wrong tenant. A Bicep
// deployment has no equivalent: the scope comes from the CLI context, and
// nothing in the file can constrain it. Emitting it means "az deployment tenant
// what-if" shows which tenant is about to be written to, which is the closest
// this gets to the same guard. Check it before applying.
@description('Tenant the deployment ran against. Compare with az account show --query tenantId before applying.')
output deployedToTenantId string = tenant().tenantId
