// Subscription placement and cost guardrails.
//
// The alias API creates a subscription at the tenant root and it's moved
// afterward, so creation and placement are separate resources here too.
//
// A tenant deployment, because Microsoft.Subscription/aliases is tenant only.
// That needs more access than the Terraform version; see bicep/README.md.
//
//   az deployment tenant create --location westus2 \
//     --template-file main.bicep --parameters main.bicepparam

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
// DemoSubscription predates the landing zone, so it goes under Corp (audit
// only). Moving it to Corp turns enforcement on. See ADR 0005.
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
// The ID is a parameter, so it can be a module scope directly. In vending it
// comes from the deployment and has to cross a nesting boundary first.
module brownfieldBudget '../modules/subscription-budget/main.bicep' = {
  scope: subscription(brownfieldSubscriptionId)
  name: 'budget-${brownfieldSubscriptionName}'
  params: {
    name: 'budget-${brownfieldSubscriptionName}'
    amount: monthlyBudgetAmount
    contactEmails: budgetAlertEmails
  }
}

// The subscription baseline for the adopted brownfield subscription. Vended
// subscriptions get theirs from modules/subscription-vending.
module brownfieldBaseline '../modules/subscription-baseline/main.bicep' = {
  scope: subscription(brownfieldSubscriptionId)
  name: 'baseline-${brownfieldSubscriptionName}'
  params: {
    securityContactEmails: budgetAlertEmails
  }
}

// ---------------------------------------------------------------------------
// Subscription vending
// ---------------------------------------------------------------------------
// Creating a subscription needs a billing role on the invoice section, billing
// profile or account; Azure RBAC grants nothing there. The onboarding runbook
// covers it. Placement follows ADR 0003.
//
// vend = false keeps a planned subscription in the list without creating it.
var subscriptions = [
  {
    displayName: 'sub-management'
    managementGroupName: '${prefix}-platform-management'
    vend: true
  }
  {
    displayName: 'sub-connectivity'
    managementGroupName: '${prefix}-platform-connectivity'
    vend: true
  }
  {
    displayName: 'sub-corp-payments-prod'
    managementGroupName: '${prefix}-lz-corp'
    vend: false
  }
  {
    displayName: 'sub-online-portal-prod'
    managementGroupName: '${prefix}-lz-online'
    vend: true
  }
]

module subscriptionVending '../modules/subscription-vending/main.bicep' = [
  for vendedSubscription in subscriptions: if (createSubscriptions && vendedSubscription.vend) {
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
// Skipped until managementSubscriptionId is set. The Terraform version gates on
// createSubscriptions, but what matters is whether the subscription exists.
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
