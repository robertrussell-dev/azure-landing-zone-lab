# Modules

The Bicep side of [`modules/`](../../terraform/modules/). Same four, same rule:
two callers before I pull anything out, and two of these still don't meet it.

| Module | Callers | What it does |
|---|---|---|
| [`policy-assignment`](policy-assignment/) | 5 | Policy assignment at management group scope, and the role assignments its identity needs. |
| [`subscription-budget`](subscription-budget/) | 2 | Subscription budget, actual and forecast thresholds. |
| [`subscription-vending`](subscription-vending/) | 1 | Creates a subscription against a billing scope, places it, budgets it. Calls `subscription-budget`. |
| [`spoke-network`](spoke-network/) | 1 | One spoke virtual network, its subnets, route table and both halves of the hub peering. |

The reasoning behind the rule is in [modules/README.md](../../terraform/modules/README.md)
and I'm not going to repeat it. What's below is the part that's different
because it's Bicep.

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

That's why I only apply the two caller rule to what lands in this directory.
Scope shims stay next to the root module that needs them, because they're not
reusable and pretending otherwise would fill `modules/` with files nobody can
call.

## No moved blocks

The Terraform README has a section on `moved` blocks, because pulling a
resource into a Terraform module changes its address and Terraform reads an
address change as destroy plus create. `prevent_destroy` on
`azurerm_subscription` caught that twice while the modules were being
extracted.

I had nothing to write here. ARM identifies a resource by its type, name and
scope. Moving the declaration into a module, renaming the
symbol, reordering a loop: none of it changes any of those three, so the next
deployment matches the existing resource and does nothing.

The flip side is that a Bicep refactor gives you nothing to review. A Terraform
`moved` block is a claim in the config that a reviewer can check against the
plan. Here the equivalent assurance is `az deployment ... what-if`, and it only
exists at the moment you run it.

## Interface differences

**`subscription_id` isn't a parameter anywhere.** The Terraform
`subscription-budget` takes a bare GUID, validates it's not a resource ID, and
builds the scope itself, because everyone passes the resource ID once and the
apply time error doesn't point at what they did. The Bicep module takes the
subscription as its deployment scope instead, so the caller writes
`scope: subscription(guid)` and the mistake isn't available to make.

`subscription-vending` is the exception that proves it: it has to pass a
subscription ID as a parameter, because the subscription doesn't exist yet.
That's what its second file is for.

**`policyDescription`, not `description`.** A parameter named `description`
shadows the `@description` decorator for the rest of the file, and every
decorator after it fails to compile with an error naming the decorator rather
than the parameter. Ten minutes of confusion, recorded at the declaration so
nobody spends them again.

**Empty string instead of null.** Terraform's `null` means "not set" and
`policy-assignment` uses it for `location` and `non_compliance_message`. Bicep
parameters can't default to null without declaring the type as nullable, so I
defaulted these to `''` and tested with `empty()`. Same behaviour, slightly
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

The one that matters most is in
[`subscription-vending/vended-subscription.bicep`](subscription-vending/vended-subscription.bicep).
On its own that file looks like pointless indirection, so the comment names the
rule it exists to satisfy and quotes the error you get without it. It's the
Bicep counterpart of the `time_sleep` comment in the Terraform module: a thing
that looks like clutter until you know what it's load bearing for.

The `time_sleep` itself has no counterpart. See
[`policy-assignment`](policy-assignment/), which explains what replaced it.
