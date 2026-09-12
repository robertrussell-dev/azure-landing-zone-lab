# subscription-budget

A subscription budget with an actual-spend alert and a forecast alert.

## Why this is a module

Two callers today: the adopted brownfield subscription and the platform
management subscription. Every subscription this platform vends gets one, so
the caller count grows with the estate.

## Usage

```hcl
module "budget" {
  source = "../../modules/subscription-budget"

  name            = "budget-management"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  amount          = 20
  contact_emails  = ["platform-oncall@example.com"]
}
```

Overriding the thresholds:

```hcl
module "budget" {
  source = "../../modules/subscription-budget"

  name            = "budget-corp-payments-prod"
  subscription_id = var.payments_subscription_id
  amount          = 5000
  contact_emails  = ["payments-oncall@example.com", "finops@example.com"]

  actual_threshold_percent   = 90
  forecast_threshold_percent = 110
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | Budget name. Immutable once created. |
| `subscription_id` | string | required | Bare GUID, not a resource ID. The module builds the scope. |
| `amount` | number | required | Budget amount in the billing account currency. |
| `contact_emails` | list(string) | required | At least one. A budget with no contacts alerts nobody. |
| `actual_threshold_percent` | number | `80` | Alert on spend already incurred. |
| `forecast_threshold_percent` | number | `100` | Alert on projected spend. The one that leaves time to act. |
| `time_grain` | string | `Monthly` | `Monthly`, `Quarterly` or `Annually`. |

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

**`time_period` is ignored after creation.** The start date derives from
`timestamp()`, so without `ignore_changes` every plan would show a diff on a
value nobody intended to change.

## Validation

Inputs are validated rather than trusted: `subscription_id` must be a bare GUID
(passing a full resource ID is the common mistake, and it fails at apply time
with an unhelpful error otherwise), `amount` must be positive, and
`contact_emails` must be non-empty.
