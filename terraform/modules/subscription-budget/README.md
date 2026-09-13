# subscription-budget

A subscription budget with an actual-spend alert and a forecast alert.

## Why this is a module

Three callers today: the adopted brownfield subscription, every subscription
`subscription-vending` creates, and the connectivity network in
`90-optional-network`.

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
| `contact_emails` | list(string) | required | At least one. |
| `actual_threshold_percent` | number | `80` | Alert on spend already incurred. |
| `forecast_threshold_percent` | number | `100` | Alert on projected spend. |
| `time_grain` | string | `Monthly` | `Monthly`, `Quarterly` or `Annually`. |

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

**`time_period` is ignored after creation**, because the start date comes from
`timestamp()`, which changes on every plan.

## Validation

`subscription_id` must be a bare GUID, since a full resource ID fails at apply
with an unhelpful error. `amount` must be positive and `contact_emails`
non-empty.
