# ADR 0006: Private DNS zones are owned by the platform

Status: Accepted
Date: 2026-09-06

## Context

Private endpoints need private DNS zones to resolve. Someone has to own those
zones, and the two candidates pull in opposite directions.

Centralized, in the Connectivity subscription: one authoritative set of
`privatelink.*` zones, one place to audit, consistent resolution for hybrid
clients. Workload teams cannot create their own.

Workload owned: the team that creates a private endpoint owns the zone it
resolves through, in their own subscription, with no dependency on a platform
process to make their deployment work.

This is the contested one, and Microsoft's documentation contradicts itself.

## The documentation conflict

The Azure Virtual Machines baseline architecture **in an Azure landing zone**
lists, under *Workload team-owned resources*:

> **Private endpoints** provide private IP-based access to platform services
> over the Azure backbone. In this architecture, they secure connectivity to
> platform as a service (PaaS) solutions and **the private DNS zones required
> for those endpoints**.

The same article, in its Networking section, says the opposite:

> In this architecture, **the platform team ensures the reliable private DNS
> resolution** for private link endpoints. Collaborate with your platform team
> to understand their expectations.

Both statements are in one document. The likely explanation is visible in the
article's own framing: the workload-owned list opens by saying those resources
"remain mostly unchanged from the baseline architecture", so the private DNS
zone line appears to be carried over from the standalone baseline, where the
workload does own its zones. The Networking section is the part
written about the landing zone change.

The Microsoft Foundry landing zone architecture removes the ambiguity by
stating the delta explicitly:

> *Change from the baseline:* In the baseline architecture, the workload team
> directly manages the private DNS zones. In this architecture, the platform
> team typically maintains private DNS zones.

So: in a standalone baseline the workload owns the zones, and in a landing
zone the platform does. The contradiction is one article inheriting a list from
another. Citing the VM baseline article for workload ownership inside a landing
zone quotes a line its own networking section overrides.

## Decision

**Private DNS zones for private endpoints are owned by the platform team and
hosted in the Connectivity subscription.**

The implementation is Microsoft's documented pattern at scale, three policies:

1. **Deny** creation of `Microsoft.Network/privateDnsZones` with a
   `privatelink` prefix in workload subscriptions. Otherwise a workload team
   clicking "Integrate with private DNS zone: Yes" in the portal creates a
   competing zone.
2. **DeployIfNotExists** to create the `privateDnsZoneGroup` on the private
   endpoint, registering its record in the central zone.
3. The DINE assignment's managed identity holds **Private DNS Zone
   Contributor** in the subscription and resource group hosting the zones. The
   endpoint is in the workload subscription and the zone is in Connectivity, so
   the identity needs rights in a subscription other than the one it acts on.

Azure landing zones ship a policy initiative for this, `Configure Azure PaaS
services to use private DNS zones`, which is preferable to hand-rolling
definitions that then need maintaining as Azure adds services.

## What centralization costs

**Deployment now depends on an asynchronous platform process.** The DINE policy
creates the DNS record after the private endpoint exists. A workload that
deploys a private endpoint and immediately depends on resolving it can fail.
Microsoft documents this for Foundry Agent Service explicitly: deploy before
the record is resolvable from the subnet and the deployment fails. The workload
team cannot fix this themselves, because they have no rights in the zone.

This is mitigated by **creating the private DNS zones at vending time, ahead of
the workload deployment.** The zones a landing
zone will need are created and linked as part of subscription vending, so the
namespace is already resolvable before the workload team deploys anything into
it. The race remains possible for a service type nobody anticipated, which is
why adding a zone is a platform request with a turnaround rather than an
unbounded wait.

**Infrastructure as code drifts.** DINE policies add resources the
workload's own templates did not declare, so the deployed state and the
declared state disagree. Microsoft's guidance is to incorporate the
platform-initiated changes into the workload's templates pre-emptively rather
than reconcile them imperatively afterward.

This platform already hit the same class of problem with a Modify policy
appending `costCenter`, where Terraform then planned to remove the tag and the
policy re-added it. The resolution there was to name an owner for the field and
have Terraform ignore it. The DNS case is the same problem at a larger scale.

**A slow platform team becomes a workload team's outage.** Centralized
ownership means every new PaaS service type needs a zone the platform team
creates. Until they do, workloads using that service cannot resolve privately.
That queue is the cost of the control.

## What to ask a client to determine which model they need

Five questions decide it:

1. **Do on premises clients need to resolve private endpoints?** If yes,
   centralization is close to forced. Hybrid resolution needs one authoritative
   view, reached through a DNS Private Resolver inbound endpoint or a forwarder
   inside a virtual network, because `168.63.129.16` is unreachable from on
   premises.
2. **Is there a platform team that can carry a request queue?** Centralization
   converts a workload team's self-service action into a ticket. Without
   someone to answer it, the control becomes a bottleneck that teams route
   around.
3. **How many workload teams share the tenant?** One or two teams do not need
   the governance overhead. Many teams make an unowned namespace unmanageable.
4. **Does a compliance regime require demonstrating that private endpoints
   resolve privately?** If auditors need one place to look, distributed
   ownership makes the evidence hard to produce.
5. **How fast do teams need to adopt new Azure services?** A team adopting
   services faster than the platform team can add zones will feel
   centralization as friction.

## Alternatives considered

**Workload owned zones.** Each team owns the zones for its own endpoints.
Fastest for the team, no platform dependency, no queue. Rejected here because
hybrid resolution then has no authoritative answer, and because nothing
prevents two teams creating conflicting zones for the same namespace, which is
a resolution failure that presents as an intermittent application bug.

**Sharded zones with delegated ownership.** The middle path, and the first to
revisit at scale. Multiple zones partitioned by team, environment
or service, each with independent service limits, each linked only to the
virtual networks that need it. Application teams get RBAC on the zones they
own; the platform team keeps audit and policy across the namespace. Microsoft
notes that a monolithic zone tends to require broad permissions across teams,
which is its own risk.

Not chosen because this lab has one operator and no scale problem. The
triggers would be: multiple teams in one tenant,
frequent automated DNS change, a need to reduce change blast radius, or a zone
growing past tens of thousands of records.

## Consequences

- Workload teams cannot create `privatelink` zones, and the portal's
  "Integrate with private DNS zone" option must be set to No. That surprises
  teams, so it belongs in the onboarding runbook.
- The platform team owns a queue: every new PaaS service type needs a zone
  before any workload can use it privately.
- Private endpoint deployments have an asynchronous dependency on a policy the
  workload team cannot see or fix. Failures look like the workload's problem
  and are not.
- Workload IaC must anticipate resources it did not declare, or accept
  permanent drift.
- If this lab grew multiple independent teams, sharded zones with delegated
  RBAC would be the next design, not a return to workload ownership.
