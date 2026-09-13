// Subscription vending: create a subscription, place it, budget it.
//
// Unlike the Terraform module, this also creates the budget inside the new
// subscription. vended-subscription.bicep shows how.
//
// Tenant scoped, because Microsoft.Subscription/aliases is, so its callers are
// too.

targetScope = 'tenant'

@description('Subscription display name. Also the default alias and the budget name suffix.')
@minLength(3)
@maxLength(60)
param displayName string

@description('Alias object name. Defaults to displayName. Immutable, and reusing an existing alias adopts that subscription rather than creating a new one.')
param aliasName string = ''

@description('Invoice section, billing profile or billing account resource ID the subscription is billed to. Permissions here are a separate model from Azure RBAC: management group Owner grants nothing at billing scope.')
param billingScopeId string

@description('Name of the management group to place the subscription under. This determines the inherited policy and role assignments, so it is the archetype decision from ADR 0003 made concrete.')
param managementGroupName string

@description('Production or DevTest. DevTest attracts lower rates and requires an eligible billing plan. Immutable after creation.')
@allowed([
  'Production'
  'DevTest'
])
param workload string = 'Production'

@description('Tags applied to the subscription. A Modify policy may add more, and a redeploy removes them again unless the caller merges them in. See the README.')
param tags object = {}

@description('Monthly budget in the billing account currency. Every vended subscription gets one.')
@minValue(1)
param budgetAmount int = 50

@description('Who is alerted when the budget threshold is crossed. The workload team on call contact, not the platform team.')
@minLength(1)
param budgetContactEmails array

@description('Alert threshold on actual spend, as a percentage of the budget.')
param budgetActualThresholdPercent int = 80

@description('Alert threshold on forecast spend, as a percentage of the budget. This is the one that leaves time to act.')
param budgetForecastThresholdPercent int = 100

resource subscriptionAlias 'Microsoft.Subscription/aliases@2021-10-01' = {
  // The alias names the alias object and is immutable. Reusing an existing one
  // adopts that subscription instead of creating a new one.
  name: empty(aliasName) ? displayName : aliasName

  properties: {
    displayName: displayName
    billingScope: billingScopeId
    workload: workload

    additionalProperties: {
      tags: tags
    }
  }
}

// Placement and the budget need the ID as a parameter; see that file's header.
module vended 'vended-subscription.bicep' = {
  name: take('vend-${displayName}', 64)
  params: {
    subscriptionId: subscriptionAlias.properties.subscriptionId
    managementGroupName: managementGroupName
    budgetName: 'budget-${displayName}'
    budgetAmount: budgetAmount
    budgetContactEmails: budgetContactEmails
    budgetActualThresholdPercent: budgetActualThresholdPercent
    budgetForecastThresholdPercent: budgetForecastThresholdPercent
  }
}

@description('Bare GUID of the created subscription.')
output subscriptionId string = subscriptionAlias.properties.subscriptionId

@description('Full resource ID, for use as a scope in policy or role assignments.')
output subscriptionResourceId string = '/subscriptions/${subscriptionAlias.properties.subscriptionId}'

@description('Management group the subscription was placed under.')
output managementGroupId string = vended.outputs.managementGroupId

@description('Resource ID of the subscription budget.')
output budgetId string = vended.outputs.budgetId

@description('Steps vending leaves to the caller. See the module README.')
output remainingSteps array = [
  'Register resource providers in the new subscription. A new subscription has almost none, and the failure is a 409 naming the namespace rather than the cause.'
  'Register Microsoft.PolicyInsights specifically, or the subscription reports no policy compliance.'
  'Deploy workload resources. Anything whose resource name depends on the new subscription ID needs a second deployment, for the same reason placement does.'
  'Assign workload team access at subscription or resource group scope, never at management group scope.'
]
