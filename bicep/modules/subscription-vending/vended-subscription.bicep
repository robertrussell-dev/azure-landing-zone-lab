// Everything that needs the new subscription's ID.
//
// A resource name or module scope must be known before the deployment starts,
// and the alias's subscriptionId isn't. Using it directly in main.bicep
//
//   name: subscriptionAlias.properties.subscriptionId          // the placement
//   scope: subscription(subscriptionAlias.properties.subscriptionId)  // the budget
//
// fails with BCP120. A nested deployment's parameters are known when it starts,
// so the ID is passed in here as one. Azure Quickstart's
// create-subscription-resourcegroup sample does the same.

targetScope = 'tenant'

@description('GUID of the subscription. A runtime value at the caller, which is why this file exists.')
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

// Placement. The same resource places adopted subscriptions, so the alias's
// own managementGroupId property isn't used.
resource placement 'Microsoft.Management/managementGroups/subscriptions@2023-04-01' = {
  parent: managementGroup
  name: subscriptionId
}

// Waits for placement; the onboarding runbook says why.
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

// Defender's free tier. Budget contacts also get the security alerts.
module baseline '../subscription-baseline/main.bicep' = {
  scope: subscription(subscriptionId)
  name: take('baseline-${budgetName}', 64)
  params: {
    securityContactEmails: budgetContactEmails
  }
  dependsOn: [
    placement
  ]
}

@description('Resource ID of the budget.')
output budgetId string = budget.outputs.id

@description('Management group the subscription was placed under.')
output managementGroupId string = managementGroup.id
