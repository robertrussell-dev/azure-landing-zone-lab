// Subscription placement and cost guardrails.
//
// Placement is deliberately separate from creation. Subscriptions created
// through the alias API land in the tenant root management group and are moved
// afterwards, so "create" and "place" are always two operations. Modelling them
// separately matches what actually happens rather than hiding it.
//
// Management group scopes are resolved by name for the same reason as
// bicep/10-policy: the names are derived from the prefix, so nothing needs to
// be passed between root modules and each directory deploys independently.
//
// Scope. Tenant, and not by preference. Microsoft.Subscription/aliases is a
// tenant scoped resource type, so anything that vends a subscription has to be
// a tenant deployment:
//
//   az deployment tenant create --location westus2 \
//     --template-file main.bicep --parameters main.bicepparam
//
// The Terraform equivalent runs against a subscription scoped provider and
// reaches tenant level resources through it, so this directory asks for more
// access than terraform/20-subscription-placement does. README.md has the
// comparison.

targetScope = 'tenant'

@description('Same prefix used by bicep/00-management-groups.')
@minLength(2)
@maxLength(10)
param prefix string

@description('GUID of the pre existing subscription adopted into the hierarchy under the audit only Corp archetype.')
param brownfieldSubscriptionId string

@description('Short name used in the budget resource name. Not the subscription display name.')
param brownfieldSubscriptionName string = 'demo'

@description('Monthly budget in the billing account currency. A budget notifies, it does not cap spending.')
@minValue(1)
param monthlyBudgetAmount int = 20

@description('Addresses notified when a budget threshold is crossed. Kept in the parameter file because it is personal data.')
@minLength(1)
param budgetAlertEmails array

@description('Whether to vend subscriptions. Creation is a billing account operation, so it is behind a flag rather than implied by a deployment.')
param createSubscriptions bool = false

@description('Invoice section resource ID subscriptions are billed to. Format: /providers/Microsoft.Billing/billingAccounts/{ba}/billingProfiles/{bp}/invoiceSections/{is}. Empty when createSubscriptions is false.')
param billingScopeId string = ''

@description('GUID of the management subscription. Set after it is created, so that resources inside it target the right subscription. The central workspace is skipped while this is empty.')
param managementSubscriptionId string = ''

@description('Region for resources created inside the management subscription.')
param location string = 'westus2'

// ---------------------------------------------------------------------------
// Brownfield placement
// ---------------------------------------------------------------------------
// DemoSubscription predates this landing zone. It is the brownfield case, and
// it is placed under the audit only Corp archetype rather than Corp itself.
//
// What this demonstrates, and the reason it is worth doing rather than
// describing: the subscription is now evaluated against the Corp policy set,
// including the Deny on public IPs, and none of it is enforced. Compliance is
// measured with zero risk to whatever is running. Moving this association to
// the real Corp management group is the single change that turns enforcement
// on, with no policy rewritten. See ADR 0005.
resource corpAudit 'Microsoft.Management/managementGroups@2023-04-01' existing = {
  name: '${prefix}-lz-corp-audit'
}

resource brownfieldPlacement 'Microsoft.Management/managementGroups/subscriptions@2023-04-01' = {
  parent: corpAudit
  name: brownfieldSubscriptionId
}

// ---------------------------------------------------------------------------
// Budget on the adopted subscription
// ---------------------------------------------------------------------------
// The subscription already exists, so its ID is a parameter and can be used
// directly as a module scope. Contrast the vending module, where the same value
// is produced by the deployment and has to cross a nesting boundary first.
module brownfieldBudget '../modules/subscription-budget/main.bicep' = {
  scope: subscription(brownfieldSubscriptionId)
  name: 'budget-${brownfieldSubscriptionName}'
  params: {
    name: 'budget-${brownfieldSubscriptionName}'
    amount: monthlyBudgetAmount
    contactEmails: budgetAlertEmails
  }
}

// ---------------------------------------------------------------------------
// Subscription vending
// ---------------------------------------------------------------------------
// The alias API creates the subscription against a billing scope and the
// platform team places it. Both steps belong to the platform team, and both are
// in the vending module.
//
// Billing scope permissions are a separate model from Azure RBAC. Owner on a
// management group grants nothing here. The caller needs Owner, Contributor or
// Azure subscription creator on the invoice section, billing profile or billing
// account. That split is the most common blocker when a team first automates
// this, and the onboarding runbook calls it out.
//
// Placement is the archetype decision from ADR 0003 made concrete: it is what
// determines the policy set and role assignments each subscription inherits.
var subscriptions = [
  {
    displayName: 'sub-management'
    managementGroupName: '${prefix}-platform-management'
  }
  {
    displayName: 'sub-connectivity'
    managementGroupName: '${prefix}-platform-connectivity'
  }
  {
    displayName: 'sub-corp-payments-prod'
    managementGroupName: '${prefix}-lz-corp'
  }
  {
    displayName: 'sub-online-portal-prod'
    managementGroupName: '${prefix}-lz-online'
  }
]

module subscriptionVending '../modules/subscription-vending/main.bicep' = [
  for vendedSubscription in subscriptions: if (createSubscriptions) {
    name: take('vend-${vendedSubscription.displayName}', 64)
    params: {
      displayName: vendedSubscription.displayName
      billingScopeId: billingScopeId
      managementGroupName: vendedSubscription.managementGroupName
      budgetAmount: monthlyBudgetAmount
      budgetContactEmails: budgetAlertEmails
      tags: {
        costCenter: 'lab'
        autoDelete: 'false'
      }
    }
  }
]

// ---------------------------------------------------------------------------
// Central Log Analytics workspace, in the management subscription
// ---------------------------------------------------------------------------
// Skipped while managementSubscriptionId is empty, rather than gated on
// createSubscriptions the way the Terraform version is. The condition that
// matters is whether there is a subscription to deploy into, and after the
// first vending run that is true whether or not the flag is still set.
//
// Two files rather than one because the resource group and the workspace sit at
// different scopes, and a module is how a Bicep deployment changes scope. They
// stay in this directory rather than in modules/ because there is one caller,
// which is the rule in modules/README.md.
module managementLogs 'management-logs.bicep' = if (!empty(managementSubscriptionId)) {
  scope: subscription(managementSubscriptionId)
  name: 'management-logs'
  params: {
    prefix: prefix
    location: location
  }
}

@description('Where the adopted subscription now sits, and what that means for enforcement.')
output brownfieldPlacementSummary object = {
  subscriptionId: brownfieldSubscriptionId
  managementGroup: corpAudit.name
  enforcement: 'DoNotEnforce, policies evaluated but not acted on'
  toEnforce: 'move this association to ${prefix}-lz-corp'
}

@description('Resource ID of the central workspace, or an empty string while the management subscription is unset. Feed this to bicep/10-policy to switch the DeployIfNotExists assignment on.')
output logAnalyticsWorkspaceId string = empty(managementSubscriptionId) ? '' : managementLogs!.outputs.workspaceId
