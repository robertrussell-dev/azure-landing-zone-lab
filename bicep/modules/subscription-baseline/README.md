# subscription-baseline

The part of the subscription baseline that Azure Policy can't do: Defender for
Cloud's free posture tier and a security contact. Activity log streaming and
Service Health alerts are policy in [`bicep/10-policy`](../../10-policy/).

The Bicep counterpart of
[`terraform/modules/subscription-baseline`](../../../terraform/modules/subscription-baseline/).
Everything it creates is free.

## Why this is a module

Two callers: [`subscription-vending`](../subscription-vending/), through
`vended-subscription.bicep`, for every subscription it creates, and
`bicep/20-subscription-placement` for the adopted brownfield subscription.

## Usage

```bicep
module baseline '../modules/subscription-baseline/main.bicep' = {
  scope: subscription(subscriptionId)
  name: 'baseline-${subscriptionName}'
  params: {
    securityContactEmails: [
      'platform-security@example.com'
    ]
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `securityContactEmails` | array | `[]` | Who Defender emails about high severity alerts, on top of the owners. Empty skips the contact. |

The subscription is the module's deployment scope, not a parameter.

## Outputs

| Name | Description |
|---|---|
| `cspmTier` | The Defender posture tier it set. `Free` is Foundational CSPM. |

## Notes

**No resource provider registration, unlike the Terraform module.** A Bicep
deployment registers the providers for the resource types it declares, so
deploying these two resources registers `Microsoft.Security` on its own.
Terraform has to register it explicitly. Nothing here declares a
`Microsoft.PolicyInsights` type, though, so a subscription deployed only from
the Bicep tree has to have that registered separately before it reports policy
compliance.

**`Free`, never `Standard`.** `CloudPosture` at `Free` is Foundational CSPM,
which costs nothing. `Standard` is the paid Defender CSPM plan, billed per
resource.

**checkov flags both resources.** Six checks want paid Defender plans, or read
the retired security contact schema. Each is recorded with its reason in
[`.checkov.yml`](../../../.checkov.yml).

**what-if agrees with Terraform.** Against the Terraform-deployed brownfield
subscription, both resources come back `NoChange`.
