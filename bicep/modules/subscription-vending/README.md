# subscription-vending

Creates an Azure subscription against a billing scope, places it in a
management group, and gives it a budget.

The Bicep counterpart of
[`modules/subscription-vending`](../../../terraform/modules/subscription-vending/). It's
the platform capability an application team consumes, and it exists so that
onboarding a landing zone is one reviewed change rather than a sequence of
portal steps somebody half remembers.

Two files, and the second one isn't optional. See
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
| `remainingSteps` | What this module deliberately does not do. |

## Why there are two files

![Subscription vending nesting](../../../docs/diagrams/vending-nesting.svg)

`vended-subscription.bicep` looks like indirection for its own sake. It isn't,
and this is the part of the Bicep tree worth reading if you only read one.

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

A **parameter** of a nested deployment is resolvable by the time that nested
deployment begins. So the value is passed one level down as a parameter, and on
the other side of that boundary it's usable as a name and as a scope. That's
the whole of what the second file does. Azure Quickstart's
`create-subscription-resourcegroup` sample uses the same double nesting for the
same reason.

## What this module does and the Terraform one doesn't

**Vending is one deployment here, not two applies.**

The Terraform module's README says it cannot deploy resources inside the new
subscription, because a provider block needs a `subscription_id` at plan time
and the subscription doesn't exist until apply. That's true and it isn't a
design preference over there.

Bicep has the same constraint and a way through it, which is the nesting above.
So this module places and budgets the subscription in the run that creates it,
and a team asking for a landing zone gets one deployment rather than two.

Don't over-read that. Anything that needs the subscription to be *reachable*
rather than just identifiable still can't happen here.

## What this module does not do, and why

**It does not register resource providers.** That's an operation inside the
subscription and there's no ARM resource for it. A new subscription has almost
none registered, and the failure is a 409 naming the namespace rather than the
cause:

```
MissingSubscriptionRegistration: The subscription is not registered to use
namespace 'Microsoft.OperationalInsights'
```

Register `Microsoft.PolicyInsights` even though nothing asks for it. Without it
the subscription reports **no policy compliance at all**, and the silence is
indistinguishable from a scan that hasn't run yet.

**It does not deploy workload resources.** Not a limitation of the tool so much
as of the module: that's the workload team's deployment, not the platform
team's, and the boundary is the point.

The `remainingSteps` output lists these so they're surfaced rather than
remembered.

## Operational notes

**Place before deploying.** Subscriptions created through the alias API land in
the tenant root management group. The creator's Owner assignment on a freshly
created subscription has been observed not to grant effective access: every
write returns `AuthorizationFailed` for far longer than propagation explains,
and neither re-authenticating nor waiting helps. Placing the subscription under
a management group where the operator holds Owner resolves it immediately. The
budget module here carries an explicit `dependsOn` on the placement for that
reason, not for ordering ARM would have worked out.

**Placement is a separate resource, deliberately.** The alias API can place the
subscription itself, through `additionalProperties.managementGroupId`. It isn't
used. A subscription being adopted from an existing estate is moved with
`Microsoft.Management/managementGroups/subscriptions` and nothing else, so
using the same resource for a new one keeps a single code path - which is
exactly what `bicep/20-subscription-placement` relies on for the brownfield
case.

**There is no `prevent_destroy`.** The Terraform module sets it on
`azurerm_subscription` because `terraform destroy` would otherwise cancel a
live subscription.

The risk doesn't take the same shape here, and it's worth being clear about why
rather than claiming Bicep is safer. There's no `bicep destroy`. An incremental
deployment never removes a resource just because it left the template, and
incremental is the only mode available: Complete mode, which does delete what
the template doesn't declare, is
[resource group scoped only](https://learn.microsoft.com/azure/azure-resource-manager/templates/deployment-modes)
and this module deploys at tenant scope. So the accident `prevent_destroy`
guards against isn't reachable from here at all.

What is reachable is a [deployment stack](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks),
which is the current mechanism for managing deletion and does work at tenant
scope. A stack with `--action-on-unmanage deleteResources` that stops listing
this alias is the Bicep shaped version of the same mistake. Nothing here uses
stacks, and adopting them would want a `denySettings` decision made
deliberately rather than picked up along the way.

The other difference: an alias can't be updated. Microsoft's documentation is
explicit that `Microsoft.Subscription/aliases` creates a subscription and
changes to its properties afterwards aren't retained. Renaming a subscription
is a separate Rename operation, not an edit here.

**Tags and Modify policies fight, quietly.** If a Modify assignment appends
tags, ARM will PUT the `tags` value from this module over what's there and the
policy will put its own back on the next evaluation. Terraform at least shows
you that argument in a plan; here there's nothing to look at. Decide who owns
each key. See `bicep/25-brownfield-seed/main.bicep` for the worked example and
what it costs to fix properly.
