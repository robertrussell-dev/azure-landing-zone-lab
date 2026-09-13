# subscription-budget

A subscription budget with an actual-spend alert and a forecast alert.

The Bicep counterpart of
[`modules/subscription-budget`](../../../terraform/modules/subscription-budget/).

## Why this is a module

Three callers today: the adopted brownfield subscription, every subscription
`subscription-vending` creates, and the connectivity network in
`90-optional-network`.

## Usage

The subscription is the deployment scope, not a parameter:

```bicep
module budget '../modules/subscription-budget/main.bicep' = {
  scope: subscription('00000000-0000-0000-0000-000000000000')
  name: 'budget-management'
  params: {
    name: 'budget-management'
    amount: 20
    contactEmails: [
      'platform-oncall@example.com'
    ]
  }
}
```

Overriding the thresholds:

```bicep
module budget '../modules/subscription-budget/main.bicep' = {
  scope: subscription(paymentsSubscriptionId)
  name: 'budget-corp-payments-prod'
  params: {
    name: 'budget-corp-payments-prod'
    amount: 5000
    contactEmails: [
      'payments-oncall@example.com'
      'finops@example.com'
    ]
    actualThresholdPercent: 90
    forecastThresholdPercent: 110
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | Budget name. Immutable once created. |
| `amount` | int | required | Budget amount in the billing account currency. |
| `contactEmails` | array | required | At least one. |
| `actualThresholdPercent` | int | `80` | Alert on spend already incurred. |
| `forecastThresholdPercent` | int | `100` | Alert on projected spend. |
| `timeGrain` | string | `Monthly` | `Monthly`, `Quarterly` or `Annually`. |
| `startDate` | string | first of the current month | Start of the budget period, `yyyy-MM-dd`. See below. |
| `endDate` | string | `''` | End of the budget period, `yyyy-MM-dd`. Empty lets Azure default it to ten years after the start. |

The subscription is set by the caller with `scope:`, not passed as an input.

## Outputs

| Name | Description |
|---|---|
| `id` | Resource ID of the budget. |
| `thresholds` | The configured thresholds, for reporting and tests. |

## Notes

**A budget notifies; it doesn't cap spending or stop a deployment.** Azure
Policy is what prevents deployments.

**Actual and forecast thresholds.** The forecast alert fires before the money
is spent, which is the one you can act on.

**`startDate` is a parameter because there's no `ignore_changes`.** The
Terraform module derives it from `timestamp()` and ignores later changes.
Here it defaults to the first of the current month, so a redeploy in a later
month tries to move the start date. Pin it in the `.bicepparam` file once the
budget exists. (It's a parameter because `utcNow()` only works as a default.)
Pinning also helps what-if, which can't evaluate `utcNow()` and prints the raw
expression.

**Notifications are a named map.** Renaming a key replaces that notification.
Terraform's provider named its keys `actual_GreaterThan_80.000000_Percent` and
`forecasted_GreaterThan_100.000000_Percent`, and this module uses `actual` and
`forecasted`, so deploying over the Terraform budget would replace both. Copying
the generated names isn't worth it, since they change with the threshold.

**No subscription validation.** The Terraform module checks for a bare GUID.
Here `scope: subscription(x)` either resolves or doesn't compile.
