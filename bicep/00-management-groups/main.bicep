// Management group hierarchy, composed by hand.
//
// The Bicep counterpart of terraform/00-management-groups. Same tree, same reasons,
// recorded in the same ADRs. The Azure Verified Modules ALZ pattern module, and
// its Bicep sibling ALZ-Bicep, would generate this and a great deal more. Both
// are deliberately not used, for the reason in ADR 0007: the point of this
// directory is that every group and every parent relationship is visible and
// explainable in one file.
//
// Depth note: Azure allows six levels below the tenant root group. This tree
// uses three, which leaves room to insert a level later without restructuring.
//
// Scope. Management groups are tenant level resources, but this is not a
// tenant deployment. It runs at the tenant root management group and creates
// each group with scope: tenant():
//
//   az deployment mg create --management-group-id <tenantId> \
//     --location westus2 --template-file main.bicep \
//     --parameters main.bicepparam
//
// The groups land in exactly the same place either way. What changes is where
// the deployment record is written, and so what the operator needs rights to.
//
// A tenant deployment needs a role assignment at "/", the true root scope.
// That scope takes built in roles only, so the narrowest grant available there
// is Contributor over the entire tenant. The tenant root management group is
// an ordinary RBAC scope: it accepts custom roles, so a principal can be given
// Microsoft.Resources/deployments/* and Microsoft.Management/managementGroups/*
// there and nothing else. That is the reason for the change, and it is the
// difference between a grant you can scope and one you cannot.
//
// Microsoft documents this shape specifically for principals that cannot
// deploy at the tenant:
// https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-management-group#management-group
//
// The cost is that the deployment scope and the resource scope no longer
// match, which is one more thing to hold in your head when reading the file.
// Every group below therefore states scope: tenant() rather than inheriting
// it. 20-subscription-placement has no equivalent escape, because
// Microsoft.Subscription/aliases is tenant scoped and cannot be created from
// anywhere else.

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
