# subscription-vending

Creates an Azure subscription against a billing scope, places it in a
management group, and gives it a budget.

This is the platform capability an application team consumes. It exists so
that onboarding a landing zone is one reviewed change rather than a sequence of
portal steps somebody half remembers.

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
| `remaining_steps` | What this module deliberately does not do. |

## What this module does not do, and why

**It does not deploy resources inside the new subscription.**

This is a Terraform limitation rather than a design preference. A provider
block needs a `subscription_id` at plan time, and the subscription does not
exist until apply. You cannot configure a provider for a subscription this
module is about to create in the same run.

So vending a landing zone is **two applies**:

1. This module creates and places the subscription and gives it a budget.
2. A second configuration, with an `azurerm` provider aliased to the new
   subscription ID, registers resource providers and deploys into it.

A module that pretended otherwise would work once, from a state file that
already had the subscription, and fail for the next person running it from
scratch.

**It does not register resource providers.** Same reason: that is an operation
inside the subscription. A new subscription has almost none registered, and the
failure is a 409 naming the namespace rather than the cause:

```
MissingSubscriptionRegistration: The subscription is not registered to use
namespace 'Microsoft.OperationalInsights'
```

Register `Microsoft.PolicyInsights` even though nothing asks for it. Without
it the subscription reports **no policy compliance at all**, and the silence is
indistinguishable from a scan that has not run yet.

The `remaining_steps` output lists these so they are surfaced rather than
remembered.

## Operational notes

**Place before deploying.** Subscriptions created through the alias API land in
the tenant root management group, and the creator's Owner assignment on a
freshly created subscription has been observed not to grant effective access:
every write returns `AuthorizationFailed` for far longer than propagation
explains, and neither re-authenticating nor waiting helps. Placing the
subscription under a management group where the operator holds Owner resolves
it immediately. Since placement is required anyway, do it first.

**`prevent_destroy` is set on the subscription.** Destroying the resource
cancels the subscription. Removing one is a deliberate act performed outside
this workflow, and the Decommissioned management group exists to hold the
result.

**Recovering from a partial create.** If the apply fails partway, Terraform
marks the resource tainted and the next plan proposes replacement, which for a
subscription means cancellation. `prevent_destroy` blocks that. The recovery is
`terraform untaint`, not a re-run.

**Tags and Modify policies fight.** If a Modify assignment appends tags, this
module's `tags` value will disagree with reality and Terraform will plan to
remove what the policy added. Decide who owns each key and have the caller
ignore the policy-owned ones. See `infra/25-brownfield-seed` for a worked
example.
