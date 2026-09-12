// Everything that has to wait until the new subscription has an ID.
//
// This file exists because of one Bicep rule: a resource name, and a module
// scope, must be resolvable before the deployment starts. The subscription ID
// produced by an alias is not. Writing either of these in main.bicep
//
//   name: subscriptionAlias.properties.subscriptionId          // the placement
//   scope: subscription(subscriptionAlias.properties.subscriptionId)  // the budget
//
// fails at compile time with BCP120, and the message is precise about why: it
// lists the properties of the alias that can be calculated at the start, and
// subscriptionId is not among them.
//
// A parameter of a nested deployment is resolvable by the time that nested
// deployment begins. So the value crosses one deployment boundary as a
// parameter and becomes usable on the other side. That is the whole trick, and
// it is why placement and the budget live here rather than beside the alias.
//
// Azure Quickstart's create-subscription-resourcegroup sample uses the same
// double nesting for the same reason.

targetScope = 'tenant'

@description('GUID of the subscription. A runtime value at the caller, a parameter here, which is the entire reason this file exists.')
param subscriptionId string

@description('Name of the management group to place the subscription under.')
param managementGroupName string

@description('Budget name.')
param budgetName string

@description('Budget amount in the billing account currency.')
param budgetAmount int

@description('Addresses notified when a budget threshold is crossed.')
param budgetContactEmails array

@description('Alert threshold on actual spend.')
param budgetActualThresholdPercent int

@description('Alert threshold on forecast spend.')
param budgetForecastThresholdPercent int

resource managementGroup 'Microsoft.Management/managementGroups@2023-04-01' existing = {
  name: managementGroupName
}

// Placement. Subscriptions created through the alias API land in the tenant
// root management group, and this is what moves them. It is the same resource
// used to place a subscription that already exists, which is why the alias
// API's own additionalProperties.managementGroupId is not used instead: one
// code path for placement, whether the subscription is new or adopted.
resource placement 'Microsoft.Management/managementGroups/subscriptions@2023-04-01' = {
  parent: managementGroup
  name: subscriptionId
}

// Place before deploying into the subscription. A subscription whose
// authorization is inherited from a management group behaves differently from
// one relying solely on the assignment created at vending time, so the budget
// waits for the placement rather than racing it. See the onboarding runbook.
module budget '../subscription-budget/main.bicep' = {
  scope: subscription(subscriptionId)
  name: take('budget-${budgetName}', 64)
  params: {
    name: budgetName
    amount: budgetAmount
    contactEmails: budgetContactEmails
    actualThresholdPercent: budgetActualThresholdPercent
    forecastThresholdPercent: budgetForecastThresholdPercent
  }
  dependsOn: [
    placement
  ]
}

@description('Resource ID of the budget.')
output budgetId string = budget.outputs.id

@description('Management group the subscription was placed under.')
output managementGroupId string = managementGroup.id
