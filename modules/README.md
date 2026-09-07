# Modules

Three modules. Each has more than one caller, which is the test applied here.

| Module | Callers | What it does |
|---|---|---|
| [`policy-assignment`](policy-assignment/) | 5 | A policy assignment at management group scope, plus the role assignments its managed identity needs. |
| [`subscription-budget`](subscription-budget/) | 2 | A subscription budget with actual and forecast alert thresholds. |
| [`subscription-vending`](subscription-vending/) | 1, growing with the estate | Create a subscription against a billing scope, place it in a management group, budget it. Composes `subscription-budget`. |

## When a module earns its place

**At the second caller.** Not before.

A module wrapping a single resource with exactly one call site adds a
variable-passing boundary and a layer of indirection in exchange for nothing.
A reviewer is entitled to ask why it exists, and "so that the repository has a
modules folder" is not an answer.

The management group hierarchy in `infra/00-management-groups` is the worked
counter-example. It is thirteen resources with one caller and it is
deliberately **not** a module, because the point of that directory is that
every group and every parent relationship is readable in one file. Wrapping it
would make a reader chase indirection to answer "what does this create".

`subscription-vending` is the one entry above that bends the rule, and
knowingly. It has a single caller today. It is a module because it is the
platform capability an application team consumes, the caller count grows with
every landing zone the platform vends, and the sequencing it encodes (create,
then place, then budget, and why deployment into the subscription cannot happen
in the same apply) is knowledge that belongs somewhere reusable rather than
inline in one root module.

## What these modules are trying to demonstrate

Interface design over resource wrapping. Specifically:

- **Inputs validated rather than trusted.** `subscription_id` must be a bare
  GUID, because passing a full resource ID is the common mistake and it
  otherwise fails at apply time with an unhelpful error. A budget must have at
  least one contact, because a budget that alerts nobody is decoration.
- **Behaviour switched by data, not by flags.** Passing
  `role_definition_ids` to `policy-assignment` is what creates a managed
  identity, so an Audit assignment never grows an identity it cannot use.
- **Comments that carry the reason, not the mechanics.** Every non-obvious
  line says why it is there. The `time_sleep` before a role assignment is the
  clearest case: without the note it reads as superstition, and with it, it
  reads as a documented `PrincipalNotFound` race.
- **Documented limits.** `subscription-vending` says plainly what it does not
  do and why Terraform cannot do it, rather than leaving the next person to
  discover that a provider cannot be configured for a subscription that does
  not exist at plan time.

## Refactoring into modules

Both extractions here were done with `moved` blocks, and both plans came back
`0 to add, 0 to change, 0 to destroy`.

That matters more than it sounds. Restructuring changes a resource's address,
and Terraform reads an address change as destroy-then-create. For a budget that
is noise. For a subscription it means cancellation, which is exactly what
`prevent_destroy` on `azurerm_subscription` caught, twice, during this
refactor.

`moved` blocks are the reviewable version of `terraform state mv`: they live in
the configuration, they appear in the plan, and the next person can see what
happened.
