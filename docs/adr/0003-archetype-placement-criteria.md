# ADR 0003: Archetype placement criteria

Status: Proposed
Date: 2026-09-06

## Context

A workload arrives and the platform team has to place its subscription under
Corp, Online, Local or Sandboxes. Placement determines the policy set and the
role assignments the subscription inherits, so it is the decision that shapes
everything else about that landing zone.

The rule has to be written down, because the intuitive question is the wrong
one. Most people reach for "is it internet facing?" and that question does not
determine the archetype.

## Decision

**The archetype is determined by whether the workload requires routed
connectivity to the corporate network through the hub. Nothing else.**

Applied in order:

1. Does it run on, or manage, Azure Local clusters? Place under **Local**. The
   policy requirements differ enough that it is its own archetype.
2. Is it experimentation with no promotion path to production? Place under
   **Sandboxes**. Isolated from the hub, deliberately loose policy.
3. Does it require routed connectivity to on premises systems, or to other Corp
   workloads, through the hub? Place under **Corp**.
4. Otherwise place under **Online**.

Internet exposure appears nowhere in that sequence. It is a real design
question and it is answered inside the landing zone, not by choosing one.

## Why internet facing is the wrong question

Microsoft's own workload guidance is explicit that public applications sit
under Corp or Online depending on whether they also need hybrid routing. The
two properties are orthogonal:

| Workload | Needs hybrid routing | Internet ingress | Archetype |
|---|---|---|---|
| Marketing site, no corporate backend | No | Yes | Online |
| Monolithic customer portal reading an on premises ERP | Yes | Yes | **Corp** |
| Internal HR application | Yes | No | Corp |
| Public API, cloud native backend | No | Yes | Online |
| Nightly batch pulling an on premises file share | Yes | No | Corp |
| Data science spike, no promotion path | n/a | n/a | Sandboxes |

Row two is the one that matters. A public, internet facing customer portal
belongs under Corp if it reads from an on premises system, because its
connectivity requirement is what the archetype governs. Placing it under Online
because it is public would put a workload with a hybrid dependency in the
archetype that does not provide hybrid routing.

Note the word monolithic. See the next section, which is the more common and
usually better answer.

## The rule applies to a landing zone, not to an application

A landing zone is a subscription. An application is not required to be one.

If an application decomposes into components with different connectivity
requirements, the answer is usually two landing zones rather than one placement
compromise. The public front end goes to Online. The component that talks to
the on premises system goes to Corp. The rule is unchanged, it is simply
applied per component.

That is normally the better design, because it minimises what needs corporate
routing. A compromised public front end is not already inside the corporate
routing domain, and it does not consume coordinated address space it has no use
for.

The mechanism that makes it clean is Private Link. The Corp component is
published behind a Private Link Service and the Online component consumes it
through a private endpoint in its own virtual network. No hybrid route is
required, no spoke to spoke peering is created, and the traffic does not
transit the corporate network.

The cost, and the reason this is not automatic: two landing zones means two
vending requests, two subscriptions, two sets of role assignments and budgets,
and a cross boundary integration that somebody operates and debugs. For a small
application that overhead is real, and a single Corp landing zone is the
defensible choice. The question to ask at intake is whether the hybrid
dependency is the whole application or one component of it.

## What the archetype actually buys

Corp carries policy that assumes traffic reaches the internet through the hub,
so egress can be inspected centrally. Here that is enforced
concretely: a Deny on public IP addresses attached to network interfaces,
assigned at Corp and deliberately absent from Online.

That single policy is the archetype's meaning made operational. Under Corp, the
route to the internet is the hub. Under Online, direct connectivity is the
point, and the same policy would be nonsense.

## The cost of getting it wrong

Placement is not a label. Moving a subscription between archetype management
groups has consequences, in increasing order of expense.

**Policy changes immediately.** The subscription inherits the new archetype's
assignments as soon as it moves. Existing resources are evaluated against the
new set at the next scan, and a workload that was compliant can become
non compliant in bulk without anything about it changing.

**Deny does not remove what already exists.** A Deny effect blocks creation and
modification. Resources that already violate it keep running and become
undeployable, which is a worse state than either compliant or blocked, because
it is discovered at the next release rather than at the move.

**DeployIfNotExists does not backfill.** Moving into an archetype with a
DeployIfNotExists assignment does not retroactively configure existing
resources. That requires an explicit remediation task, and forgetting it
produces a subscription that reports compliant policy assignment while the
resources predating the move are untouched.

**Addressing cannot be retrofitted.** This is the expensive one. Corp requires
the workload's virtual network to be peered to the hub, which requires its
address space to come from the platform supernet and not overlap anything
already allocated. A workload placed under Online is likely to have been given
address space nobody coordinated. Moving it to Corp later means renumbering,
which means rebuilding the virtual network and everything attached to it.

The addressing consequence is why the connectivity question is asked at intake
rather than inferred later. It is the one part of this decision that cannot be
undone with a management group move.

## Where this rule breaks

Every decision rule handles some case badly. This one has two.

**A workload consumed by both Corp and Online workloads.** A shared service
owned by an application team rather than the platform team has consumers on
both sides of the boundary. The rule gives no answer, and either placement
strands half the consumers. In practice this is resolved by publishing the
service through Private Link rather than by placing it, which means the
archetype question was the wrong question for that workload.

**The rule cannot express a one directional requirement.** It conflates needing
to reach on premises with being reachable from on premises. Corp membership
grants routed connectivity, and routes work in both directions. A workload that
must pull data from an on premises system but should never be reachable from
the corporate network gets more than it asked for, by construction.

The compensating controls for that second case are network security groups and
firewall rules, which live outside the archetype. The archetype decides
reachability in principle, and something else has to decide it in practice. The
rule is a good default that does not remove the need for a network design
conversation on workloads where direction matters.

## Alternatives considered

**Place by business unit or by application team.** Rejected. Microsoft's
guidance is explicit that the hierarchy should not re-create the organisational
chart, and organisational structure changes more often than connectivity
requirements do. A reorganisation should not trigger a subscription migration.

**Place by data classification, for example a PCI archetype.** Not done here,
but it is the correct pattern when a compliance regime applies to a subset of
workloads and not the estate. A new archetype under Landing Zones is the safest
place to extend the hierarchy. This becomes a second placement dimension rather
than a replacement for the connectivity rule.

**Ask the workload team to choose.** Rejected. They optimise for their own
delivery, and the archetype encodes a platform commitment about routing and
inspection. The platform team asks the connectivity question and applies the
rule.

## Consequences

- Placement is decidable from one question at intake, so it can be part of a
  subscription vending request rather than a design discussion.
- Internet facing workloads exist in both Corp and Online, which will look
  wrong to anyone who assumes the archetypes mean public and private. The
  naming invites that misreading and the runbook states the rule explicitly to
  counter it.
- Corp is the more expensive archetype to join, because it consumes coordinated
  address space. Workloads with no hybrid requirement should not be placed
  there for the sake of consistency.
- Sandboxes have no promotion path by definition. A workload that turns out to
  matter is provisioned a new landing zone rather than promoted in place, since
  the sandbox has been running under deliberately loose policy.
