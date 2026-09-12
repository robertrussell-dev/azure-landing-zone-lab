# subscription-baseline

The part of the subscription baseline that Azure Policy can't do: resource
provider registration, Defender for Cloud's free posture tier, and a security
contact. The rest of the baseline, activity log streaming and Service Health
alerts, is policy in [`terraform/10-policy`](../../10-policy/), because policy
reaches every subscription under the intermediate root on its own.

Everything it creates is free.

## Why this is a module

Two callers: [`subscription-vending`](../subscription-vending/) for every
subscription it creates, and `terraform/20-subscription-placement` for the
adopted brownfield subscription, which vending didn't create.

## Why azapi

azurerm registers providers and sets Defender plans in the subscription its
provider block points at, and there's no subscription argument to override
that. One provider block per subscription can't be generated in a loop, so
azurerm would need a hand-written alias for every subscription, including ones
that don't exist yet. azapi addresses any subscription by resource ID, so one
module covers them all, including a subscription vended earlier in the same
apply.

## Usage

```hcl
module "baseline" {
  source = "../modules/subscription-baseline"

  subscription_id         = azurerm_subscription.this.subscription_id
  security_contact_emails = ["platform-security@example.com"]
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `subscription_id` | string | required | GUID of the subscription. |
| `security_contact_emails` | list(string) | `[]` | Who Defender emails about high severity alerts, on top of the owners. Empty skips the contact. |
| `resource_providers` | list(string) | `Microsoft.Security`, `Microsoft.PolicyInsights`, `Microsoft.Insights` | Providers to register. |

## Outputs

| Name | Description |
|---|---|
| `registered_providers` | The providers it registered. |
| `cspm_tier` | The Defender posture tier it set. `Free` is Foundational CSPM. |

## Notes

**`Free`, never `Standard`.** In the Defender pricing API, `CloudPosture` at
`Free` is Foundational CSPM, which costs nothing. `Standard` is the paid
Defender CSPM plan, billed per resource. From 27 October 2026 new subscriptions
don't get the free tier by default any more, which is why it's set here rather
than assumed.

**Registering `Microsoft.Security` switches on two more plans.** Azure sets
`FoundationalCspm` and `Discovery` to `Standard` on its own. Neither has a
billing meter in the retail prices API, so `Standard` there means "on", not
"paid".

**It also changes what policy reports.** Registering `Microsoft.Security` makes
Defender auto assign its Microsoft Cloud Security Benchmark initiative at
subscription scope. That's audit only, and its findings are Defender's
recommendations, not this repo's assignments.

**The pricing isn't deleted on destroy.** `azapi_update_resource` changes the
existing `CloudPosture` plan in place and leaves it alone on destroy, because
the plan can't be deleted. The security contact is removed as normal.

**Registration is asynchronous.** It returns while the provider is still
registering, so a 60 second `time_sleep` sits between registration and the
Defender settings.
