// A subscription budget with two alert thresholds.
//
// Two thresholds rather than one, and the distinction matters:
//
//   Actual      fires on money already spent. Tells you what happened.
//   Forecasted  fires on projected spend for the period. Tells you what is
//               about to happen, which is the only one that leaves time to act.
//
// A budget notifies. It does not cap spending and it cannot stop a deployment.
// Anything that must not be deployed is prevented by Azure Policy, not by a
// budget. Treating a budget as a control rather than an alarm is how surprise
// bills happen.
//
// The subscription is the deployment scope, not a parameter. The Terraform
// module takes a bare GUID and builds the scope string itself, and validates
// the input because passing a full resource ID by mistake fails at apply time
// with an unhelpful error. Here the caller sets scope: subscription(guid) and
// the mistake is not available to make.

targetScope = 'subscription'

@description('Budget name. Immutable once created.')
@minLength(1)
@maxLength(63)
param name string

@description('Budget amount in the billing account currency.')
@minValue(1)
param amount int

@description('Addresses notified when a threshold is crossed. At least one, or the budget notifies nobody and is decoration.')
@minLength(1)
param contactEmails array

@description('Percentage of the budget at which an alert fires on actual spend. Tells you what has already been spent.')
@minValue(1)
@maxValue(1000)
param actualThresholdPercent int = 80

@description('Percentage at which an alert fires on forecast spend. This is the threshold that leaves time to act, because it fires before the money is gone.')
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

// Budgets must start on the first of a period.
//
// There is no ignore_changes in Bicep, which is what the Terraform module uses
// to stop a timestamp derived start date showing as a diff on every plan. The
// equivalent here is to make the value an input: it defaults to the first of
// the current month, and a caller that deploys across a month boundary should
// pin it in the .bicepparam file so that redeploying does not attempt to move
// the start date of a budget that already exists.
//
// utcNow is only legal as a parameter default value, which is also why this is
// a parameter rather than a variable.
@description('First day of the budget period, yyyy-MM-dd. Defaults to the first of the current month. Pin it once the budget exists.')
param startDate string = utcNow('yyyy-MM-01')

// Azure defaults this to ten years after the start date, which is what the
// budgets in this lab carry. Exposed for the same reason definitionVersion is
// exposed on the policy-assignment module: a real property of the resource
// that a caller might have an opinion about, rather than something added to
// silence a what-if line. A budget that should stop alerting on a known date
// is a legitimate thing to want.
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

    // Terraform models notifications as repeated blocks. ARM models them as a
    // named map, and the names are part of the resource: renaming a key
    // replaces that notification rather than editing it.
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
