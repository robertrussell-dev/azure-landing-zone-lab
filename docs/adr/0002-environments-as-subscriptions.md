# ADR 0002: Environments are subscriptions, not management groups

Status: Proposed
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

## Why, and why not the count argument

The usual argument against per environment management groups is arithmetic.
Thirty workloads, each with a workload group plus one per environment, produces
one hundred and twenty management groups carrying near identical policy. That
is true, and it is the weaker argument, because a team comfortable with
infrastructure as code will reasonably respond that generating one hundred and
twenty management groups is not hard.

The stronger argument is that differentiated policy per environment moves
failure to the most expensive point in the cycle.

Consider a policy requiring storage accounts to refuse public network ingress
and use private endpoints. If development does not carry that policy, the team
builds and tests against a publicly reachable storage account, and everything
works. The failure appears on promotion, when the environment that does enforce
the policy rejects the deployment. The team then reworks its architecture after
the effort is already spent.

Loose policy in development does not make developers faster. It defers the
discovery of a misconfiguration until rework is most costly. Identical policy
across environments means promotion cannot fail on policy, because there is
nothing new to fail against.

## The counterargument

Per environment management groups would make differentiated policy easier.
That is true, and it is not a trivial objection. Application teams have real
needs that vary by environment. Production may require backup, geo redundancy
and a longer log retention that development has no reason to pay for.

The answer is that the requirement is real but the mechanism is wrong. A
management group is a policy inheritance boundary, not a place to record that
production matters more. Assigning the control as an audit policy at the
archetype gives the platform team the same visibility across every environment,
while leaving the application team free to satisfy it where it applies.

The platform audits. The application team implements. The policy set stays
identical, so promotion stays safe.

## What this costs, and what it does not

The chosen mechanism enforces nothing. An audit policy reports and does not
block, so a production subscription can sit non compliant with a control the
platform considers important.

Microsoft does not prescribe what happens next. The guidance offers the shared
responsibility split, the platform team audits and the application team
implements, and stops there. The escalation path is an operating model decision
and this platform makes it explicitly.

**Escalation.** Non compliance raises a ticket automatically, assigned to the
owning team's backlog with a remediation date. Governance that depends on
someone noticing a dashboard is not governance, so the finding has to arrive
where the team already plans work.

If the date passes, the control is escalated from `Audit` to `Deny` at that
subscription for new resources, while existing resources are grandfathered. The
non compliant workload keeps running. The team cannot deploy anything new until
it is fixed.

Deleting the offending resource is not the lever. In production it is not a
credible threat, and a consequence nobody will carry out is worse than no
consequence, because the first time it is not carried out the deadline stops
meaning anything. Blocking new deployment is credible precisely because it hurts
without requiring anyone to break a running service.

**Expected non compliance is a smaller problem than it first appears.** An
exempt resource reports a compliance state of `Exempt` rather than
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

An exemption renewed twice is a policy defect, not a resource defect. If the
same waiver keeps being reissued, the control is wrong for that environment and
the policy should change rather than the exception becoming permanent by
repetition.

One trap, because it is not obvious: when `expiresOn` passes, the
exemption object is not deleted. It is retained for record keeping and simply
stops being honoured. Nothing alerts. The resource silently returns to non
compliant, so expiry is only meaningful if somebody is watching the compliance
view. Expiry is a review trigger, not a control.

## The exception

Microsoft names criteria for putting several environments in one subscription:
the environments cannot be isolated, the same teams hold the same functional
roles across them, and the environments can share a policy set. Its worked
example is Azure App Service, on the grounds that deployment slots live within
one App Service plan in one subscription, so mandating a subscription per
environment complicates the deployment lifecycle.

That example does not survive inspection. App Service slots are described in
the App Service documentation as a release mechanism: validate changes before
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

The criteria stand. The App Service example is not sufficient to meet them on
its own, and a request citing it should be asked what specifically breaks.
Where a genuine exception is granted, the workload gets one subscription,
separation moves down to resource groups, and RBAC with Privileged Identity
Management is applied at resource group scope. The exception is recorded at
subscription vending time rather than discovered later.

## Protecting the mechanism

Because differentiation now happens below the management group, the controls
that live below the management group have to be hard to quietly remove.
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
justification and logged. This is the same argument as ADR 0001: the boundary
is only worth what the access model behind it is worth.

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
- Escalation from audit to enforcement is a documented step with an owner,
  rather than an implied one that never happens.
- Sandbox remains the exception to all of this. It is a separate management
  group with a deliberately looser policy set, because it is not part of any
  promotion path.
