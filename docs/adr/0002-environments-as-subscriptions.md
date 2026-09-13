# ADR 0002: Environments are subscriptions, not management groups

Status: Accepted
Date: 2026-09-06

## Context

Development, test and production environments for one application need some
form of separation. The obvious options are a management group per environment
beneath the archetype, or a subscription per environment inside a single
archetype management group.

Microsoft's guidance is explicit on both counts. Environments should be
separate subscriptions, placed in the same archetype management group. And:

> SDLC environments shouldn't have different policies, so we don't recommend
> separate management groups.

The tailoring guidance repeats it: do not create archetypes for development,
test and production.

## Decision

One subscription per environment. All of them sit in the same archetype
management group, so `corp` holds the dev, test and production subscriptions
for a corp workload and they inherit an identical policy set.

Where an application genuinely needs a control in production that does not
apply in development, the control is assigned as an **Audit** policy at the
archetype management group, and the application team implements it in the
environments where it applies.

## Why

The usual argument against per environment management groups is the count:
thirty workloads with a group each plus one per environment is 120 management
groups with near identical policy. That's the weaker argument, because
infrastructure as code can generate 120 groups easily.

The stronger one is that different policy per environment moves failures to
the most expensive point in the cycle.

Consider a policy requiring storage accounts to refuse public network ingress
and use private endpoints. If development does not carry that policy, the team
builds and tests against a publicly reachable storage account, and everything
works. The failure appears on promotion, when the environment that does enforce
the policy rejects the deployment. The team then reworks its architecture after
the effort is already spent.

Loose policy in development doesn't make developers faster; it delays finding
the misconfiguration until rework costs most. With identical policy,
promotion can't fail on policy.

## The counterargument

Per environment management groups would make differentiated policy easier, and
application teams do have needs that vary by environment. Production may require backup, geo redundancy
and a longer log retention that development has no reason to pay for.

The requirement is real, but a management group is the wrong mechanism. It's a
policy inheritance boundary, not a way to mark production as more important.
An audit policy at the archetype gives the platform team visibility across
every environment, and the application team satisfies it where it applies. The
policy set stays identical, so promotion stays safe.

## What this costs, and what it does not

The chosen mechanism enforces nothing. An audit policy reports and does not
block, so a production subscription can sit non compliant with a control the
platform considers important.

Microsoft's guidance stops at the shared responsibility split and doesn't say
what happens next. This platform decides that here.

**Escalation.** Non compliance raises a ticket automatically, in the owning
team's backlog with a remediation date, so it arrives where the team plans work
instead of waiting for someone to check a dashboard.

If the date passes, the control is escalated from `Audit` to `Deny` at that
subscription for new resources, while existing resources are grandfathered. The
non compliant workload keeps running. The team cannot deploy anything new until
it is fixed.

Deleting the offending resource isn't the lever. Nobody will do that in
production, and once a threat isn't carried out the deadline stops meaning
anything. Blocking new deployments hurts without breaking a running service.

**Expected non compliance can be told apart from drift.** An exempt resource reports a compliance state of `Exempt` rather than
`Non-compliant`, and carries a compliance substate recording what its state
would be without the exemption. Expected non compliance in development is
therefore distinguishable from real drift in the compliance view, and both are
queryable through Azure Resource Graph on
`properties.stateDetails.complianceSubState`.

**Exemptions.** Development side exemptions are granted in the `Waiver`
category with an `expiresOn` date. Approval is recorded in the exemption's own
`metadata` block, using `requestedBy`, `approvedBy`, `approvedOn` and
`ticketRef`, so the approval lives on the object rather than beside it. The
platform team approves.

An exemption renewed twice points at the policy, not the resource: the control
is wrong for that environment and should change.

When `expiresOn` passes, the exemption isn't deleted; it just stops applying,
and nothing alerts. The resource goes back to non compliant, so expiry only
works if someone watches the compliance view.

## The exception

Microsoft names criteria for putting several environments in one subscription:
the environments cannot be isolated, the same teams hold the same functional
roles across them, and the environments can share a policy set. Its worked
example is Azure App Service, on the grounds that deployment slots live within
one App Service plan in one subscription, so mandating a subscription per
environment complicates the deployment lifecycle.

That example doesn't hold up. The App Service documentation describes slots as
a release mechanism: validate changes before
swapping into production, warm every instance before the swap so there is no
downtime, and swap back immediately to recover the last known good site. They
are a way to move a build safely into production, not a way to hold three
environments.

A production subscription can therefore run a production App Service plan with
a staging slot for zero downtime releases, while development and test sit in
their own subscriptions. Nothing about slots requires collapsing environments
into one subscription, and continuous integration has no difficulty deploying
to three subscriptions.

The constraint only appears for teams using slots as their environment chain, a
dev slot and a test slot alongside production on one plan. That is a real
pattern and this platform does not accommodate it, because it makes environment
isolation depend on a feature designed for release safety.

The criteria stand, but the App Service example doesn't meet them on its own. A
request citing it should say what specifically breaks.

**No general criterion for granting the exception has been established.** App
Service does not qualify on the grounds usually offered. What would qualify is
not yet defined, so requests are decided individually, and the burden is on the
requester to identify a platform constraint rather than an inconvenience.

It's left undefined because a criterion invented now would probably be applied
inconsistently at the first real request.

Where an exception is granted, the workload gets one subscription, separation
moves down to resource groups, and RBAC with Privileged Identity Management is
applied at resource group scope. The exception is recorded at subscription
vending time rather than discovered later.

## Protecting the mechanism

Because differentiation now happens below the management group, the controls
there have to be hard to remove.
Subscription scoped policy assignments, exemptions and resource tags can all be
changed by anyone holding elevated permissions on that subscription.

Two consequences. Security relevant policies must not depend on resource tags
in their definitions, because a subscription administrator can change a tag.
And the policy authorization actions must not be granted as always active:

- `Microsoft.Authorization/policyAssignments/*`
- `Microsoft.Authorization/policyDefinitions/*`
- `Microsoft.Authorization/policyExemptions/*`
- `Microsoft.Authorization/policySetDefinitions/*`

These are eligible through Privileged Identity Management, activated with
justification and logged, for the same reason as in ADR 0001.

## Consequences

- Promotion between environments cannot fail on policy, because every
  environment inherits the same set.
- The management group count stays proportional to archetypes, not to
  workloads multiplied by environments.
- Per environment differences are visible as audit findings rather than
  enforced, so the platform team trades enforcement for agility and must be
  willing to live with that trade.
- Expected non compliance is carried as exemptions in the `Waiver` category, so
  the compliance view distinguishes `Exempt` from `Non-compliant` rather than
  drowning real drift in known noise.
- Escalation from audit to enforcement is a documented step with an owner.
- Sandbox is the exception: a separate management group with looser policy,
  because it isn't part of any promotion path.
