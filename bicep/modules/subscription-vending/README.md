# subscription-vending

Creates an Azure subscription against a billing scope, places it in a
management group, and gives it a budget.

The Bicep counterpart of
[`modules/subscription-vending`](../../../terraform/modules/subscription-vending/),
so onboarding a landing zone is one reviewed change instead of a series of
portal steps. It has two files; see
[Why there are two files](#why-there-are-two-files).

## Usage

`Microsoft.Subscription/aliases` is a tenant scoped resource type, so the
caller has to be a tenant deployment too:

```bicep
targetScope = 'tenant'

module corpPaymentsProd '../modules/subscription-vending/main.bicep' = {
  name: 'vend-sub-corp-payments-prod'
  params: {
    displayName: 'sub-corp-payments-prod'
    billingScopeId: billingScopeId
    managementGroupName: '${prefix}-lz-corp'
    budgetAmount: 5000
    budgetContactEmails: [
      'payments-oncall@example.com'
    ]
    tags: {
      autoDelete: 'false'
    }
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `displayName` | string | required | Subscription name. 3 to 60 characters. |
| `aliasName` | string | `''` | Alias object name, defaults to `displayName`. Immutable. |
| `billingScopeId` | string | required | Invoice section, billing profile or billing account resource ID. |
| `managementGroupName` | string | required | Where to place it. This is the archetype decision from ADR 0003. |
| `workload` | string | `Production` | `Production` or `DevTest`. Immutable. |
| `tags` | object | `{}` | Subscription tags. |
| `budgetAmount` | int | `50` | Monthly budget. |
| `budgetContactEmails` | array | required | Workload team on call, not the platform team. |
| `budgetActualThresholdPercent` | int | `80` | |
| `budgetForecastThresholdPercent` | int | `100` | |

The management group is a **name** here, not a resource ID. The Terraform
module takes the full ID and validates the prefix. This one looks the group up
as an `existing` resource, which needs the name, and gets the ID back from it.

## Outputs

| Name | Description |
|---|---|
| `subscriptionId` | Bare GUID. |
| `subscriptionResourceId` | Full resource ID, for use as a scope. |
| `managementGroupId` | Where it was placed. |
| `budgetId` | Resource ID of the budget. |
| `remainingSteps` | Steps left to the caller. |

## Why there are two files

![Subscription vending nesting](../../../docs/diagrams/vending-nesting.svg)

`vended-subscription.bicep` looks like needless indirection, but it isn't.

Bicep requires a resource **name**, and a module **scope**, to be resolvable
before the deployment starts. The subscription ID produced by an alias is not:
it doesn't exist until the alias has been created. Both of these fail at
compile time in `main.bicep`:

```bicep
// the placement
resource placement 'Microsoft.Management/managementGroups/subscriptions@2023-04-01' = {
  parent: managementGroup
  name: subscriptionAlias.properties.subscriptionId
}

// the budget
module budget '../subscription-budget/main.bicep' = {
  scope: subscription(subscriptionAlias.properties.subscriptionId)
  ...
}
```

with

```
BCP120: This expression is being used in an assignment to the "name" property
of the "Microsoft.Management/managementGroups/subscriptions" type, which
requires a value that can be calculated at the start of the deployment.
Properties of subscriptionAlias which can be calculated at the start include
"apiVersion", "id", "name", "type".
```

A **parameter** of a nested deployment is resolvable when that deployment
starts, so the ID is passed one level down as a parameter and becomes usable as
a name and a scope. That's all the second file does. Azure Quickstart's
`create-subscription-resourcegroup` sample uses the same double nesting for the
same reason.

## What this module does and the Terraform one doesn't

**Vending is one deployment here, not two applies.**

The Terraform module can't deploy inside the new subscription, because a
provider needs `subscription_id` at plan time. Bicep has the same constraint
and gets through it with the nesting above, so this module places and budgets
the subscription in the same run. Anything that needs the subscription to be
*reachable*, not just identifiable, still can't happen here.

## What this module does not do, and why

**It doesn't register resource providers.** There's no ARM resource for that.
A new subscription has almost none registered, and the failure looks like this:

```
MissingSubscriptionRegistration: The subscription is not registered to use
namespace 'Microsoft.OperationalInsights'
```

Register `Microsoft.PolicyInsights` even though nothing asks for it. Without it
the subscription reports **no policy compliance**, which looks the same as a
scan that hasn't run.

**It doesn't deploy workload resources.** That's the workload team's
deployment.

The `remainingSteps` output lists these.

## Operational notes

**Place before deploying.** Subscriptions created through the alias API land in
the tenant root management group. The creator's Owner assignment on a freshly
created subscription has been observed not to grant effective access: every
write returns `AuthorizationFailed` for far longer than propagation explains,
and neither re-authenticating nor waiting helps. Placing the subscription under
a management group where the operator holds Owner fixes it immediately, which
is why the budget has an explicit `dependsOn` on the placement.

**Placement is a separate resource.** The alias API can place the subscription
itself through `additionalProperties.managementGroupId`, but adopted
subscriptions are moved with `Microsoft.Management/managementGroups/subscriptions`,
and using the same resource for new ones keeps one code path.

**There is no `prevent_destroy`.** The Terraform module sets it on
`azurerm_subscription` because `terraform destroy` would otherwise cancel a
live subscription.

The accident it guards against can't happen here. There's no `bicep destroy`,
an incremental deployment never removes a resource that left the template, and
Complete mode is
[resource group scoped only](https://learn.microsoft.com/azure/azure-resource-manager/templates/deployment-modes).
[Deployment stacks](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks)
could delete an unmanaged resource, but they don't exist at tenant scope, where
this module deploys (ADR 0008).

An alias also can't be updated: Microsoft documents that changes to its
properties after creation aren't kept. Renaming a subscription is a separate
Rename operation.

**Tags and Modify policies fight without anything showing it.** A redeploy
overwrites the tags a Modify policy added, and the policy puts them back at the
next evaluation. Decide who owns each key; see
[bicep/README.md](../../README.md#the-modify-policy-fight-is-silent-instead-of-loud).
