# subscription-vending

Creates an Azure subscription against a billing scope, places it in a
management group, gives it a budget, and applies the platform baseline through
[`subscription-baseline`](../subscription-baseline/).

It makes onboarding a landing zone one reviewed change instead of a series of
portal steps.

## Usage

```hcl
module "corp_payments_prod" {
  source = "../../modules/subscription-vending"

  display_name     = "sub-corp-payments-prod"
  billing_scope_id = var.billing_scope_id

  management_group_id = data.azurerm_management_group.corp.id

  budget_amount         = 5000
  budget_contact_emails = ["payments-oncall@example.com"]

  tags = {
    autoDelete = "false"
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `display_name` | string | required | Subscription name. Lowercase, digits, hyphens. |
| `alias` | string | `null` | Alias object name, defaults to `display_name`. Immutable. |
| `billing_scope_id` | string | required | Invoice section, billing profile or billing account resource ID. |
| `management_group_id` | string | required | Where to place it. This is the archetype decision from ADR 0003. |
| `workload` | string | `Production` | `Production` or `DevTest`. Immutable. |
| `tags` | map(string) | `{}` | Subscription tags. |
| `budget_amount` | number | `50` | Monthly budget. |
| `budget_contact_emails` | list(string) | required | Workload team on call, not the platform team. |
| `budget_actual_threshold_percent` | number | `80` | |
| `budget_forecast_threshold_percent` | number | `100` | |

## Outputs

| Name | Description |
|---|---|
| `subscription_id` | Bare GUID. |
| `subscription_resource_id` | Full resource ID, for use as a scope. |
| `management_group_id` | Where it was placed. |
| `budget_id` | Resource ID of the budget. |
| `remaining_steps` | Steps left to the caller. |

## What this module does not do, and why

**It doesn't deploy workload resources inside the new subscription.** An azurerm
provider needs `subscription_id` at plan time, and the subscription doesn't
exist until apply.

The platform baseline is the exception. `subscription-baseline` uses azapi,
which addresses a subscription by resource ID rather than through a provider
block, so it works on a subscription created earlier in the same apply.

So vending a landing zone is **two applies**:

1. This module creates, places, budgets and baselines the subscription.
2. A second configuration, with an `azurerm` provider aliased to the new
   subscription ID, deploys the workload into it.

A module that tried to do both in one apply would work once, from a state file
that already had the subscription, and fail when run from scratch.

**It registers only the providers the platform uses.** A new subscription has
almost none registered, and the failure looks like this:

```
MissingSubscriptionRegistration: The subscription is not registered to use
namespace 'Microsoft.OperationalInsights'
```

The baseline registers `Microsoft.Security`, `Microsoft.Insights` and
`Microsoft.PolicyInsights`. Nothing asks for the last one, but without it the
subscription reports **no policy compliance**, which looks the same as a scan
that hasn't run. A workload registers anything else it needs.

The `remaining_steps` output lists what's left.

## Operational notes

**Place before deploying.** Subscriptions created through the alias API land in
the tenant root management group, and the creator's Owner assignment on a
freshly created subscription has been observed not to grant effective access:
every write returns `AuthorizationFailed` for far longer than propagation
explains, and neither re-authenticating nor waiting helps. Placing the
subscription under a management group where the operator holds Owner fixes it
immediately, so placement comes first.

**`prevent_destroy` is set on the subscription**, because destroying it cancels
the subscription. Cancel by hand, outside Terraform.

**Recovering from a partial create.** If the apply fails partway, Terraform
marks the resource tainted and the next plan proposes replacement, which for a
subscription means cancellation. `prevent_destroy` blocks that. The recovery is
`terraform untaint`, not a re-run.

**Tags and Modify policies fight.** Terraform plans to remove tags a Modify
assignment added. Decide who owns each key and ignore the policy-owned ones, as
`terraform/25-brownfield-seed` does.
