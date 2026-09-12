# subscription-budget

A subscription budget with an actual-spend alert and a forecast alert.

The Bicep counterpart of
[`modules/subscription-budget`](../../../terraform/modules/subscription-budget/).

## Why this is a module

Two callers today: the adopted brownfield subscription and every subscription
`subscription-vending` creates. Every subscription this platform vends gets
one, so the caller count grows with the estate.

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
| `contactEmails` | array | required | At least one. A budget with no contacts alerts nobody. |
| `actualThresholdPercent` | int | `80` | Alert on spend already incurred. |
| `forecastThresholdPercent` | int | `100` | Alert on projected spend. The one that leaves time to act. |
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

**A budget notifies, it does not cap.** It cannot stop a deployment or halt
spending. Anything that must not be deployed is prevented by Azure Policy.
Treating a budget as a control rather than an alarm is how surprise bills
happen.

**Two thresholds, deliberately.** Actual tells you what has been spent.
Forecasted tells you what is about to be spent, and is the only one that gives
you time to do something about it.

**`startDate` is a parameter because there is no `ignore_changes`.**

The Terraform module derives the start date from `timestamp()` and then adds
`ignore_changes = [time_period]`, because otherwise every plan shows a diff on
a value nobody meant to change. Bicep has no such escape hatch: whatever the
template says is what gets sent.

So the value is an input, defaulting to the first of the current month.
Deployed twice in the same month that's stable. Deployed again the following
month the default moves, and the deployment will try to change the start date
of a budget that already has one. Pin it in the `.bicepparam` file once the
budget exists and the question goes away.

`utcNow()` is only legal in a parameter default, which is the other reason this
can't be a variable.

There's a second reason to pin it, found by running a preview: what-if cannot
evaluate `utcNow()` at all. It reports the raw expression,
`"[format('{0}T00:00:00Z', utcNow('yyyy-MM-01'))]"`, against the stored date, so
it can't tell you whether the value is about to move. A pinned date is the only
way to make that line of a preview mean anything.

**Notifications are a map, not repeated blocks.** Terraform writes two
`notification` blocks. ARM wants an object keyed by a name you choose, and that
name is part of the resource: renaming `actual` to `actualSpend` replaces the
notification rather than editing it. The keys here are `actual` and
`forecasted`.

A what-if against the budget Terraform deployed shows what that costs across
tools. The provider named its notifications
`actual_GreaterThan_80.000000_Percent` and
`forecasted_GreaterThan_100.000000_Percent`; this module names them `actual`
and `forecasted`. Identical thresholds, recipients and effects, different keys,
so a deployment deletes one pair and creates the other. Copying the generated
names would close the diff and isn't worth it: the threshold is baked into the
name, so it would change every time the threshold did.

**No validation on the subscription.** The Terraform module checks that
`subscription_id` is a bare GUID rather than a resource ID, because passing the
resource ID is the common mistake and it fails at apply time with an unhelpful
error. There's nothing to validate here - `scope: subscription(x)` either
resolves or the deployment doesn't compile.
