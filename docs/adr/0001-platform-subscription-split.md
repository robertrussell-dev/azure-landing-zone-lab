# ADR 0001: Keep four platform subscriptions

Status: Proposed
Date: 2026-09-06

## Context

The Azure landing zone reference architecture places four child management
groups under Platform: Identity, Management, Connectivity and Security. Each
holds one dedicated subscription. Identity hosts domain controllers. Management
hosts the Log Analytics workspace and automation. Connectivity hosts the hub,
private DNS zones and any gateways. Security hosts Microsoft Sentinel and SIEM
tooling.

Microsoft's position on this is not a preference. The subscriptions design area
states it as a prohibition:

> Establish a separate dedicated platform subscriptions for `management`,
> `security`, `connectivity`, and `identity`. Do not combine platform
> responsibilities into a single subscription.

The pressure to ignore that is real and it comes from operations, not
architecture. Every platform subscription is another thing to run.

## Decision

Keep all four. Do not collapse Security into Management, and do not collapse
the platform into a single subscription.

The reason is organisational before it is technical. At enterprise scale these
areas have dedicated people: a network team, an identity team, a security
operations function. Separate subscriptions let access be granted along those
lines rather than across them, and let one area be locked down or audited
without touching the others.

## The trade-off

Four subscriptions costs administrative surface area, and the cost is
concrete rather than vague:

- Four sets of RBAC assignments, and four sets of PIM eligible role
  configurations if privileged access is time bound.
- Four budgets and four sets of cost alerts.
- Four Defender for Cloud plan configurations, which is also four opportunities
  to enable an expensive plan by accident.
- Four scopes at which a policy exemption can be granted and then forgotten.
- Cross subscription networking for identity. Domain controllers in the
  Identity subscription must peer into the hub in the Connectivity
  subscription, so the identity plane now depends on a peering that a different
  team owns.
- Everything is a cross subscription query. Log Analytics needs explicit
  cross workspace scoping, Resource Graph queries need a subscription list, and
  a cost view that a single subscription would have given for free now needs
  grouping. This is the cost the platform team actually feels day to day.

Collapsing Security into Management costs something narrower and worse. The
Security subscription holds Sentinel, which is the record of what the platform
team did. Move it into the subscription the platform team owns, and the team
being monitored controls the monitoring of itself. That is not a theoretical
separation of duties argument. It means an incident review depends on evidence
held by a party with an interest in it.

If the same three people run the platform and the security tooling, nothing is
lost, because the separation was never real. The question is not whether the
subscriptions are separate. It is whether the people are.

## What separation does not buy

The obvious objection to this decision is that the platform team holds Owner on
all four subscriptions anyway, and any Global Administrator can grant themselves
User Access Administrator at tenant root scope at any time. If the boundary can
be crossed at will, it is reasonable to ask what it is for.

Three things, and one clear limit.

**The boundary becomes expressible.** A security team can be granted the
Security subscription without being granted the hub, the gateways or the domain
controllers. That grant is only possible if those things are in different
subscriptions. Merging subscriptions later is cheap. Separating them costs the
migration described above, so the cost of getting this wrong is asymmetric.

**Privileged access becomes an event rather than a standing condition.** With
Privileged Identity Management, Owner on the Security subscription is eligible
rather than active: time bound, requiring justification, optionally requiring
approval, and logged on activation. The question stops being "can the platform
team reach Sentinel" and becomes "can they reach it without leaving a record."

**Crossing the boundary becomes worth alerting on.** An elevation into the
Security subscription is a meaningful signal. Activity inside a subscription
somebody works in every day is not.

The limit, stated plainly: none of this defends against a Global Administrator
who elevates to tenant root. That path exists by design, and it is how this
hierarchy was created in the first place. Subscription layout is not the control
for that threat. The controls are a small number of Global Administrators, PIM
on the role itself, monitored break glass accounts, and exporting logs to
storage outside the tenant that the tenant's own administrators do not control.

Subscription separation raises the cost and the visibility of reaching the audit
record. It does not make it impossible.

## What splitting back out actually costs

"We can separate them later" is true and not free. Moving a Log Analytics
workspace between subscriptions has verified constraints:

- The move works only within the same region and the same Entra tenant. A
  cross region move is not a move, it is a rebuild, because workspace data does
  not travel across regions.
- Sentinel is offboarded from the workspace immediately. The workspace must be
  re-onboarded within 90 days to preserve existing Sentinel data.
- Alerts must be recreated. Alert permissions are keyed to the workspace
  resource ID, and that ID changes with the move.
- Workspace primary and secondary keys are regenerated. Anything holding a
  copy, such as Key Vault, must be updated.
- Solutions with linked services, including Microsoft Defender for Cloud, must
  be deleted before the move and reinstalled after. Data collection stops in
  the interval.
- The operation can take Azure Resource Manager several hours, during which
  solutions may be unresponsive.

The honest summary is that this is a weekend of planned work, not a barrier.
It is a reason to decide deliberately rather than drift into a layout, but an
ADR that presented it as a blocker would be overstating it. Any organisation
that has grown enough to need the split can afford the weekend.

## Alternatives considered

**Collapse Security into Management.** Defensible where there is no independent
security operations function: the same team runs the platform and the security
tooling, or monitoring is outsourced to a managed provider who is granted
scoped access regardless of subscription layout.

The trigger is role overlap, not headcount. Collapse is defensible while one
person is responsible for several of these areas, because the separation is
notional anyway: the same individual holds both sets of rights whichever way
the subscriptions are drawn.

It stops being defensible at the first hire whose job is to review what the
platform team did. At that point the separation is the job, and the migration
cost below becomes due.

**Collapse all four into one platform subscription.** Rejected. Beyond the
audit argument, it puts domain controllers, the hub and the SIEM inside one
blast radius and one set of subscription quotas.

**Split further, for example per region connectivity subscriptions.** Not done
here, and only justified by subscription quota limits on connectivity resources
or a data residency requirement. Microsoft names quota pressure as the specific
trigger.

## Consequences

- Policy, RBAC and budget are assigned per platform area rather than once, so
  the platform is more work to operate and more precise to govern.
- The Security subscription can be granted to a security team without granting
  access to networking or identity infrastructure.
- Cost reporting separates platform areas without relying on tags.
- Identity depends on cross subscription peering, which becomes a documented
  dependency rather than an implicit one.
- This repo runs on a personal billing account. Connectivity and Management get
  real subscriptions. Identity and Security exist as management groups with no
  subscription beneath them. That is a funding limit of the lab, not a
  revision of this decision. See the README.
