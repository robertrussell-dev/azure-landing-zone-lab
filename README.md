# Azure landing zone reference

An Azure landing zone built with Terraform, and the architecture decision
records explaining why it is shaped the way it is. This is a reference and
learning artifact running in a personal tenant, not a production deployment,
and the sections below state plainly what it does and does not include.

## Hierarchy

![Management group hierarchy](docs/diagrams/hierarchy.svg)

The tree is built under an intermediate root (`contoso`) rather than directly
under the tenant root group, so that existing subscriptions can be moved in and
the structure reorganised without touching the tenant root.

Corp, Online and Local are workload archetypes, not environments and not
business units. Environments are subscriptions inside an archetype, which is
the subject of ADR 0002.

## Architecture decision records

The decisions are the point of this repository. The Terraform exists to show
the decisions were made by someone who deployed the result.

| ADR | Decision |
|---|---|
| 0001 Platform subscription split | Keep four platform subscriptions. Names the operational cost of doing so, and the trigger condition that would make collapsing Security into Management defensible. |
| 0002 Environments as subscriptions | Dev, test and production are subscriptions inside one archetype management group. Per environment policy is handled by Audit at the archetype, not by separate management groups. |
| 0003 Archetype placement criteria | Not yet written. The decision rule a platform team applies when a new workload arrives. |
| 0004 Hub and spoke versus Virtual WAN | Not yet written. |
| 0005 Brownfield adoption, audit only | Not yet written. The mechanism is already deployed, see below. |
| 0006 Private DNS ownership | Not yet written. |

Four of the six are outstanding. They are listed rather than omitted so the
gap is visible.

## What is actually deployed

| Area | State |
|---|---|
| Management groups | 13 groups deployed, verified in the portal |
| Policy assignments | 4 live, covering Modify, AuditIfNotExists, Deny and DoNotEnforce |
| DeployIfNotExists | Written, skipped until a Log Analytics workspace exists to target |
| Subscriptions | 2. One adopted brownfield, one platform management subscription |
| Budgets | On every subscription, actual and forecast thresholds |
| Network | Not deployed. See the note on Phase 4 below |

### Policy, and why the set is small

Five assignments that can each be explained, rather than the full landing zone
default set of several hundred that nobody here could defend individually.

| Effect | Assignment | Scope |
|---|---|---|
| Modify | Append `costCenter` tag | intermediate root |
| AuditIfNotExists | Subnets should have a network security group | intermediate root |
| Deny | Network interfaces must not have public IPs | Corp only |
| DoNotEnforce | The same Deny, enforcement off | Corp (audit only) |
| DeployIfNotExists | Network security group diagnostics | Platform Management, pending |

Inheritance is demonstrated by scope. The Modify and Audit assignments apply
everywhere. The Deny applies only to Corp, because Corp workloads route egress
through the hub and a public IP on a network interface bypasses that path.
Online deliberately does not carry it, since direct internet connectivity is
what defines that archetype.

Azure Policy is not used to deploy workloads. Microsoft's guidance is a flat no
on that, and doing it would undermine the point of the repository.

### Brownfield adoption is deployed, not described

`DemoSubscription` predates this landing zone. It sits under `Corp (audit
only)`, a duplicate of the Corp archetype carrying the same policy assignments
with `enforcementMode` set to `DoNotEnforce`.

It is evaluated against the Corp policy set, including the Deny, and none of it
is enforced. Compliance can be measured with no risk to anything running.
Moving that one management group association to Corp is the entire change
required to enforce, with no policy rewritten. There is no additional cost,
because the hierarchy and the assignments are duplicated and the workloads
are not.

## Constraints, stated plainly

**Empty management groups.** `Identity`, `Security`, `Local` and
`Decommissioned` exist in the tree with no subscriptions under them. In a real
tenant Identity holds domain controllers, Security holds Sentinel and SIEM
tooling, Local holds Azure Local clusters, and Decommissioned holds cancelled
subscriptions during their retention window. They are absent here because this
is a personal billing account and each subscription costs real money to keep.

**Subscription limits.** This runs on a Microsoft Customer Agreement billing
account. Microsoft does not publish a subscription cap or a per day creation
limit for MCA, so no such constraint is claimed here. The often repeated "five
subscriptions, one per day" figure is Microsoft Online Services Program
behaviour and does not apply to this account. The real limit is that each
subscription is a thing to pay for and clean up.

**Network stack.** Not deployed. Hub and spoke, peerings and private DNS are
intended to be deployed on demand, screenshotted, and destroyed the same day,
because a gateway or firewall left running is the most expensive mistake
available in a personal lab.

**Terraform state is local.** Appropriate for a single operator lab and not
appropriate for a team. A shared backend with locking would be required the
moment a second person or a pipeline touched this.

## Modules used, and what was written by hand

Being specific about this matters, because "I used the accelerator" and
"I composed this" are different claims.

**Written by hand:**

- The management group hierarchy (`infra/00-management-groups`). Every group
  and parent relationship is visible in one file. The Azure Verified Modules
  ALZ pattern module would generate this and considerably more, and is the
  right choice for a real tenant, but a reader cannot audit what they cannot
  read.
- The policy assignments and their scope choices (`infra/10-policy`).
- Subscription vending and placement (`infra/20-subscription-placement`).
- `modules/policy-assignment`, a local module wrapping a policy assignment and
  the role assignments its managed identity requires.

**Not used:** `Azure/avm-ptn-alz/azurerm`. Noted because it is the obvious
alternative and its absence is a decision rather than an oversight.

**Built in policy definitions** are used rather than custom ones wherever they
exist. Their IDs, allowed effects and required roles were read from the
platform with `az policy definition show` rather than copied from a blog post.
Two things that turned up doing so are recorded in comments at the call sites:
the subnet network security group built in permits only `AuditIfNotExists` or
`Disabled` and cannot be the Deny example it is often presented as, and the
tagging Modify built in requires Contributor rather than Tag Contributor for
its managed identity.

## Deploying

Directories are numbered in deployment order. Each is an independent root
module with its own state, and resolves management group scopes by name rather
than by reading another directory's state, so there is no shared backend and no
ordering hidden in state files.

```bash
cd infra/00-management-groups
cp terraform.tfvars.example terraform.tfvars   # fill in tenant, subscription, prefix
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Then `infra/10-policy`, then `infra/20-subscription-placement`, the same way.

Always `plan -out` and apply the saved plan. The risk is not that Azure changed
underneath you, it is that a `.tf` file changed between reading the plan and
typing yes.

Subscription creation is behind `create_management_subscription` rather than
implied by an apply, because it is a billing account operation.

## Destroying

```bash
cd infra/20-subscription-placement && terraform destroy
cd ../10-policy                    && terraform destroy
cd ../00-management-groups         && terraform destroy
```

Reverse order. Nothing in the deployed set is billable beyond negligible
amounts, so destroying is about hygiene rather than cost.

`azurerm_subscription` carries `prevent_destroy`. Destroying it cancels the
subscription, and a `terraform destroy` that quietly cancels a platform
subscription is not a failure mode worth leaving open. Removing a subscription
is a deliberate act done outside this workflow.

## Validation

Two CI definitions run the same checks: `azure-pipelines.yml` and
`.github/workflows/validate.yml`. The checks themselves live in `scripts/`, so
the two cannot drift in what they verify. Neither holds an Azure credential.
See [docs/ci-security.md](docs/ci-security.md) for the threat model, the forked
pull request settings, and the workload identity federation design that would
be used if CI ever needed Azure access.
