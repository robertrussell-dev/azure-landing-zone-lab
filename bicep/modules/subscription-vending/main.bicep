// Subscription vending: create a subscription, place it, budget it.
//
// This is the platform capability an application team consumes. Everything a
// new landing zone needs that can be done from outside the subscription is here
// in one call.
//
// Unlike the Terraform module, "one call" here also covers the budget, which
// lives inside the new subscription. How that is possible, and what it still
// does not do, is in vended-subscription.bicep and in the README.
//
// Microsoft.Subscription/aliases is a tenant scoped resource type. It can only
// be deployed by a tenant scoped deployment, so this module is tenant scoped
// and so is any root module that calls it.

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
  // The alias is the name of the alias object, not of the subscription, and it
  // is immutable. Reusing an alias name that already exists adopts the existing
  // subscription rather than creating a second one, which is occasionally what
  // you want and more often a surprise.
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

// Placement and the budget both need the subscription's ID, which does not
// exist until this deployment runs. Bicep will not accept a runtime value as a
// resource name or as a module scope, so both move one deployment deeper and
// take the ID as a parameter. The comment at the top of that file is the
// explanation, and it is the most Bicep specific thing in this repository.
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

@description('What vending deliberately does not do, surfaced so it is not forgotten. See the module README.')
output remainingSteps array = [
  'Register resource providers in the new subscription. A new subscription has almost none, and the failure is a 409 naming the namespace rather than the cause.'
  'Register Microsoft.PolicyInsights specifically, or the subscription reports no policy compliance at all, silently.'
  'Deploy workload resources. Anything whose resource name depends on the new subscription ID needs a second deployment, for the same reason placement does.'
  'Assign workload team access at subscription or resource group scope, never at management group scope.'
]
