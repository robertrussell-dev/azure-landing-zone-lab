// A subscription budget with two alerts: actual spend, and forecast spend, which
// fires early enough to act on. A budget only notifies; it caps nothing.
//
// The caller sets the subscription as the module scope, so there's no ID to
// validate as in the Terraform module.

targetScope = 'subscription'

@description('Budget name. Immutable once created.')
@minLength(1)
@maxLength(63)
param name string

@description('Budget amount in the billing account currency.')
@minValue(1)
param amount int

@description('Addresses notified when a threshold is crossed. At least one.')
@minLength(1)
param contactEmails array

@description('Percentage of the budget at which an alert fires on actual spend. Tells you what has already been spent.')
@minValue(1)
@maxValue(1000)
param actualThresholdPercent int = 80

@description('Percentage at which an alert fires on forecast spend.')
@minValue(1)
@maxValue(1000)
param forecastThresholdPercent int = 100

@description('Budget reset period.')
@allowed([
  'Monthly'
  'Quarterly'
  'Annually'
])
param timeGrain string = 'Monthly'

// Budgets start on the first of a period. With no ignore_changes in Bicep, pin
// this in the .bicepparam file once the budget exists, or a redeploy in a later
// month tries to move it. A parameter because utcNow only works as a default.
@description('First day of the budget period, yyyy-MM-dd. Defaults to the first of the current month. Pin it once the budget exists.')
param startDate string = utcNow('yyyy-MM-01')

@description('Last day of the budget period, yyyy-MM-dd. Empty lets Azure default it to ten years after the start date.')
param endDate string = ''

resource budget 'Microsoft.Consumption/budgets@2026-06-01' = {
  name: name
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: timeGrain

    timePeriod: {
      startDate: '${startDate}T00:00:00Z'
      endDate: empty(endDate) ? null : '${endDate}T00:00:00Z'
    }

    // A named map in ARM. Renaming a key replaces that notification.
    notifications: {
      actual: {
        enabled: true
        operator: 'GreaterThan'
        threshold: actualThresholdPercent
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      forecasted: {
        enabled: true
        operator: 'GreaterThan'
        threshold: forecastThresholdPercent
        thresholdType: 'Forecasted'
        contactEmails: contactEmails
      }
    }
  }
}

@description('Resource ID of the budget.')
output id string = budget.id

@description('The configured alert thresholds, for reporting and for tests.')
output thresholds object = {
  actual: actualThresholdPercent
  forecasted: forecastThresholdPercent
}
