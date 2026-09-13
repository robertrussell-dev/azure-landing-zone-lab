# ADR 0008: Delete protection, and which mechanism goes where

Status: Accepted
Date: 2026-09-12

## Context

A few things in this platform should not be deleted by accident. When one is,
the damage lands somewhere other than where the delete happened.

- **The central workspace.** Every subscription's activity log and every
  network security group's diagnostics point at it. Delete it and log
  collection stops across the whole hierarchy, and nothing reports it, because
  the workspace is what would have.
- **The janitor** in `30-auto-delete`. It deletes billable devices that
  someone forgot to switch off. Delete it and nothing fails. The next forgotten
  firewall just runs at 30 a day until the invoice arrives.
- **Subscriptions.** Canceling one is the only way to delete it, and it is
  recoverable only for a limited window.

Azure and the tooling offer four ways to stop a delete. Each stops a different
set of people and is removed by a different permission.

## The four

| Mechanism | Enforced by | Stops | Does not stop | Removed by |
|---|---|---|---|---|
| `prevent_destroy` | Terraform, at plan time | This configuration destroying or replacing the resource | The portal, the CLI, another configuration, Bicep | Editing the file |
| `CanNotDelete` lock | Resource Manager | Every principal, Owner included, and everything under the locked scope | Subscription cancellation, data plane deletes, Terraform destroying the lock it manages first | `Microsoft.Authorization/locks/delete`: Owner, User Access Administrator |
| `DenyAction` policy | Azure Policy, at request time | DELETE on matching types for every principal, including resources created after the assignment | Resource group deletes unless the definition is Indexed with `cascadeBehaviors` deny; children deleted with their parent; subscription cancellation; locks, stacks and policy assignments, which are exempt | Deleting the assignment, or an exemption, which needs the `exempt` action on the assignment itself |
| Deployment stack `denySettings` | A deny assignment the stack owns | DELETE (optionally write) on resources the stack manages, for every principal not excluded | Resources created implicitly, data plane operations, anything the stack does not manage | Changing or deleting the stack: Azure Deployment Stack Owner at the stack's scope |

The last column decides most of this. A lock sits in the subscription, so a
subscription Owner can take it off. A `DenyAction` assignment or a stack at a
management group can't be removed or bypassed from inside the subscription,
which is ADR 0001's separation of duties argument applied to deletion.

## What building it surfaced

None of these is in Microsoft's summary tables. Each came from the detailed
documentation or an error.

- **The built in delete policy leaves the resource group path open.** "Do not
  allow deletion of resource types" is mode `All` and sets no
  `cascadeBehaviors`. A resource group delete only honors `denyAction` for
  Indexed definitions that set `cascadeBehaviors` to `deny`. So the built in
  stops `az monitor log-analytics workspace delete` and allows
  `az group delete` on the group holding the same workspace.
- **A subscription Owner can't exempt their way out of a management group
  `DenyAction`.** Creating an exemption needs `policyExemptions/write` on the
  exempted scope *and* the `exempt` action on the target assignment. The second
  lives where the assignment lives.
- **A lock in the same Terraform state as the thing it protects doesn't stop
  that state.** The lock depends on the resource, so `terraform destroy`
  removes the lock first and then deletes the resource. It stops everyone except
  the configuration that wrote it.
- **A `CanNotDelete` lock blocks more than deletes of the resource.** Role
  assignments scoped under it can't be removed, and Resource Manager can't prune
  the scope's deployment history.
- **Stacks don't exist at tenant scope.** `bicep/20-subscription-placement`
  is a tenant deployment because `Microsoft.Subscription/aliases` is tenant
  only, so it can't be a stack.
- **A stack's deny settings only cover a subscription scoped deployment.** A
  management group stack deploying a management group template with
  `denyDelete` is rejected, so a role definition and its assignment can't be
  protected by one. The janitor is split in two stacks because of it.
- **A management group stack has to sit at or immediately above the
  subscription it deploys into.** The janitor's stack lives at Platform
  Management, the management subscription's parent, not at the intermediate
  root. Both rules came from `az stack mg validate`, after the compiler and
  what-if had accepted every earlier version.
- **Bicep can't declare a lock on a resource group from subscription scope.**
  The group is a subscription level resource, but an extension resource scoped
  to it from there fails with `BCP139`. The lock goes in the resource group
  scoped file instead.

## Decision

| What | Protected by | Why that one |
|---|---|---|
| Subscriptions | `prevent_destroy` | Locks don't block cancellation, and subscriptions are exempt from `DenyAction`. The only guard left is in the tool. The Bicep tree has none. |
| Central workspace | `DenyAction` at Platform, plus a `CanNotDelete` lock on `rg-management-logs` | The policy stops a direct delete of any platform workspace, including one added later, and is out of reach of the management subscription's Owner. The lock closes the resource group path the built in leaves open. |
| The janitor (Bicep) | A stack at Platform Management with `denyDelete` over the Automation account, runbook and schedule. The role and its assignment sit in a second stack with no deny settings | The janitor is what protects the budget, so it should be the hardest thing here to tidy away. Losing the account would be silent. Losing the role assignment isn't, since every run then fails with a 403. The stacks also give this one Bicep root a real destroy. |
| The janitor (Terraform) | Nothing | See the costs below. |
| The hub network | Nothing | See the alternatives below. |

## Alternatives considered

**A custom `DenyAction` definition, Indexed, with `cascadeBehaviors` deny.**
One object covers both the direct delete and the resource group path, with no
lock. It's the better mechanism on its own terms. It isn't used because this
repository takes built in definitions wherever one exists (ADR 0007), and one
lock on one resource group is a smaller maintenance cost than a custom
definition. That flips once there's more than one platform resource group to
protect, since locks are one per group and a definition is one per hierarchy.

**A lock on its own.** It protects today's workspace from everyone except the
subscription Owner, the role most likely to be cleaning up, and doesn't cover a
second platform workspace until someone locks that too.

**`ReadOnly` rather than `CanNotDelete`.** It blocks POST requests as well as
writes, which breaks things that don't look like changes. On a Log Analytics
workspace it prevents UEBA being enabled. On a resource group holding an
Automation account it stops every runbook starting, which would disable the
janitor.

**Protecting the hub network.** A lock on `vnet-hub` is inherited by its
peerings and subnets, which are child resources, so every spoke change and every
teardown would need it removed first. A lock on `rg-hub-network` is worse. The
billable devices live in that group, so it would stop the flags and the janitor
removing them. The free layer holds no data and comes back from code in
minutes, so it isn't protected.

**Stacks for every Bicep root.** That would give the Bicep tree the destroy it
lacks, and the runbook's manual teardown would shrink to one command per root.
It also puts deny assignments on the hierarchy and the policy assignments,
which changes who can operate them in an incident. The trigger for revisiting
is the Bicep tree becoming the deployed copy.

**A stack in the Terraform tree through azapi.** `Microsoft.Resources/deploymentStacks`
is an ordinary resource, so Terraform could create one. It would mean Terraform
deploying an ARM template whose resources never appear in a plan, so the state
and the stack would both claim to own the janitor. Two sources of truth for the
same resources is the problem state exists to prevent.

## What it costs

**Teardown gets a step.** Destroying `terraform/20` now fails on the workspace
until the `deny-platform-delete` assignment is gone. The Bicep teardown has to
delete the lock before the resource group. Both are in
[the runbook](../../runbooks/deploy-and-destroy.md).

**Replacing the workspace fails at apply.** A rename or a region move destroys
and recreates it, and the delete is denied. That protects its data, but a
legitimate change now needs an exemption first.

**The two trees diverge.** The Bicep janitor is protected and the Terraform
janitor isn't. It's the only decision in this repository that depends on the
tool.

**The operator is locked out too.** The stack has no excluded principals, so
even the deploying account, with Owner at `/`, can only delete the Automation
account through `az stack mg delete`.

**The role assignment is outside the protection.** Deny settings can't cover
management group resources, so someone with rights at the intermediate root
can remove the janitor's role and leave it running uselessly. Every run then
fails with a 403, which is visible, but only to someone looking at the job
history.

**Nothing here stops a subscription being canceled** except
`prevent_destroy`, which only stops Terraform. Azure doesn't offer a control
for this, and the `Decommissioned` management group's retention window is the
only recovery.

## Consequences

- The workspace can't be deleted by anyone below the Platform management
  group, by either path.
- Deleting it deliberately leaves a trail: an exemption with a category and an
  expiry, visible in the compliance view.
- The Bicep janitor can only be removed as a whole, through its stack.
- Adding a platform resource group worth protecting is the trigger to replace
  the built in and the lock with one custom Indexed definition.
