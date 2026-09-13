# Modules

The Bicep side of [`modules/`](../../terraform/modules/). Same five, same rule:
two callers before I pull anything out, and two of these still don't meet it.

| Module | Callers | What it does |
|---|---|---|
| [`policy-assignment`](policy-assignment/) | 8 | Policy assignment at management group scope, and the role assignments its identity needs. |
| [`subscription-budget`](subscription-budget/) | 3 | Subscription budget, actual and forecast thresholds. |
| [`subscription-baseline`](subscription-baseline/) | 2 | Turns on Defender for Cloud's free tier and a security contact. |
| [`subscription-vending`](subscription-vending/) | 1 | Creates a subscription against a billing scope, places it, budgets it, baselines it. Calls `subscription-budget` and `subscription-baseline`. |
| [`spoke-network`](spoke-network/) | 1 | One spoke virtual network, its subnets, route table and both halves of the hub peering. |

The reasoning behind the rule is in
[modules/README.md](../../terraform/modules/README.md). Below is what's
different in Bicep.

![Module call graph](../../docs/diagrams/module-call-graph.svg)

The amber nodes in the Bicep panel are the subject of the next section.

## Modules aren't optional here

In Terraform a module is a way to reuse a block of configuration. In Bicep it's
also the only way to change scope. A deployment targets one scope, every
`resource` in the file has to belong to it, and a module is what crosses the
boundary.

So some of the files under `bicep/` are modules because I reused them, and some
are modules because a resource group is a subscription level resource and a
workspace inside it isn't. `20-subscription-placement/management-logs.bicep`
is the second kind. It has one caller and always will, and it's still a
separate file.

So the two caller rule only covers this directory. Scope shims stay next to the
root module that needs them, since nothing else can use them.

## No moved blocks

The Terraform README has a section on `moved` blocks, because pulling a
resource into a Terraform module changes its address and Terraform reads an
address change as destroy plus create. `prevent_destroy` on
`azurerm_subscription` caught that twice while the modules were being
extracted.

There's nothing equivalent here. ARM identifies a resource by type, name and
scope, and moving a declaration into a module, renaming the symbol or
reordering a loop changes none of those, so the next deployment does nothing.

The flip side is that a Bicep refactor gives you nothing to review. A Terraform
`moved` block is a claim in the config that a reviewer can check against the
plan. Here the equivalent assurance is `az deployment ... what-if`, and it only
exists at the moment you run it.

## Interface differences

**`subscription_id` isn't a parameter, with one exception.** The Terraform
`subscription-budget` takes a bare GUID and validates it isn't a resource ID.
The Bicep module takes the subscription as its deployment scope, so the caller
writes `scope: subscription(guid)` and can't get it wrong.

`subscription-vending` does pass the ID as a parameter, because the
subscription doesn't exist yet. That's what its second file is for.

**`policyDescription`, not `description`.** A parameter named `description`
shadows the `@description` decorator, and every decorator after it fails with
an error that names the decorator, not the parameter.

**Empty string instead of null.** Terraform's `null` means "not set" and
`policy-assignment` uses it for `location` and `non_compliance_message`. Bicep
parameters can't default to null without declaring the type as nullable, so I
defaulted these to `''` and tested with `empty()`. Same behavior, slightly
worse spelling.

**Conditional creation reads the same and works differently.** Terraform uses
`count = condition ? 1 : 0` and callers index into `[0]`. Bicep puts the
condition on the declaration, `module x '...' = if (condition)`, and the caller
reaches outputs through `x!.outputs.y`. The `!` is a non-null assertion, and if
the condition is false at deployment time and something reads the output
anyway, that's a deployment error rather than a compile error. Both roots that
do this guard the read with the same condition.

## What the comments say

Same standard as the Terraform modules: comments say why, not what.

The most important one is in
[`subscription-vending/vended-subscription.bicep`](subscription-vending/vended-subscription.bicep).
That file looks like pointless indirection, so its comment names the rule it
satisfies and the error you get without it.

The `time_sleep` has no counterpart here; [`policy-assignment`](policy-assignment/)
explains why.
