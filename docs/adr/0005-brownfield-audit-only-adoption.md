# ADR 0005: Brownfield adoption through an audit only duplicate hierarchy

Status: Accepted
Date: 2026-09-06

## Context

Most landing zone engagements are not greenfield. Subscriptions already exist,
they run production workloads, and the teams that own them did not ask for a
governance program. Applying an enforcing policy set to those subscriptions
on day one is how a platform team becomes the reason a release failed.

The problem is that policy compliance cannot be assessed without assigning the
policy, and assigning the policy is what creates the risk.

## Decision

**Duplicate the archetype management group and its policy assignments, with
`enforcementMode` set to `DoNotEnforce`, and place adopted subscriptions there
first.**

This is deployed. `Corp (audit only)`
(`contoso-lz-corp-audit`) carries the same Deny assignment as `Corp`, with
enforcement off. `DemoSubscription`, which predates the landing zone, sits
under it.

Moving that one management group association from `contoso-lz-corp-audit` to
`contoso-lz-corp` is the entire change required to enforce. No policy is
rewritten, no assignment is edited, and the policy set the subscription was
measured against is the policy set that begins enforcing.

Microsoft notes this costs nothing extra, because it duplicates the hierarchy
and the assignments, not the workloads.

## What DoNotEnforce actually does

The portal and the API use different words for the same setting:

| Portal label | JSON value | Effect enforced | Activity log entry |
|---|---|---|---|
| Enabled | `Default` | Yes | Yes |
| Disabled | `DoNotEnforce` | No | **No** |
| Enroll | `Enroll` | Only for enrolled scopes | For enrolled resources |

`Disabled` in the portal is `DoNotEnforce` in JSON. Two consequences:

**No activity log entries are written.** You cannot measure the audit period by
counting would-have-been-denied events, because none are recorded. Measurement
has to come from compliance state, which is the next section.

**DeployIfNotExists remediation still works.** Remediation tasks can be started
for `deployIfNotExists` policies even under `DoNotEnforce`. So the audit period
is not purely observational. Missing diagnostic settings and similar
deployment shaped gaps can be closed while nothing is being blocked, which
means the subscription arrives at the enforcement decision already partly
remediated.

## What to measure before enforcing

Microsoft's guidance says to move the subscription once compliance is "in the
required state" without defining it, so it's defined here.

Enforcement is turned on when all of the following hold:

1. **Zero non-compliant resources against the Deny policies.** Deny is the only
   effect that can break a deployment, so it is the only one that must be at
   zero. A Deny doesn't remove existing violations, it makes them
   undeployable, so one remaining violation becomes a failed release at some
   later date.
2. **Audit findings triaged, not necessarily fixed.** Every non-compliant
   resource against an Audit effect has either a remediation date or a
   `Waiver` exemption with an expiry. The problem is unreviewed findings, not
   unfixed ones.
3. **DeployIfNotExists remediated during the audit period**, not deferred to
   after the move. Remediation works under `DoNotEnforce`, so there's no reason
   to wait.
4. **One full change cycle observed.** At least one real deployment by the
   workload team has occurred while the audit assignment was in place, and its
   resources evaluated compliant. A static subscription proves the resources
   are fine, not that the team's pipeline produces compliant ones, and the
   pipeline is what will hit the Deny.

Point four is the one most likely to be skipped, and it adds about a sprint to
every adoption. It's kept because it's the only one that tests the pipeline.

## Alternatives considered

Microsoft's brownfield article describes the duplicate hierarchy and doesn't
mention the next two, which are newer and lighter.

**`Enroll` enforcement mode.** A single assignment on the real archetype, in
`Enroll` mode. Scopes without an enrollment resource behave as though the
assignment were `DoNotEnforce`; enforcement begins for a scope when its owner
creates an enrollment. This achieves staged enforcement **without duplicating
the hierarchy at all**, and moves the decision to the scope owner rather than
requiring a subscription move by the platform team.

Not chosen because the duplicate hierarchy shows the state in the portal tree:
anyone can see which subscriptions are being assessed without querying
enrollment resources. At this size that's worth more than the saved management
groups.

With enough adoptions in flight at once, that reverses. I don't know the
number, but the count of concurrent adoptions, not the size of the
environment, should trigger the review.

**Resource selectors for gradual rollout.** An assignment can carry
`resourceSelectors` that narrow evaluation by resource location or type, so
enforcement is rolled out region by region rather than subscription by
subscription. This composes with either approach and is the right tool when the
risk is concentrated in a resource type rather than in a team.

**Assign enforcing policy directly and handle the breakage.** Rejected. It's
the default when nobody decides, and it makes the platform team's first contact
with every workload team a broken deployment.

## Consequences

- The hierarchy carries a management group per archetype under adoption. With
  three archetypes that is manageable. With many, this approach does not scale
  and `Enroll` mode should be revisited.
- The audit only group is not a permanent home. **Ninety days is the limit.** A
  subscription still there after that triggers a review and escalation, because
  one that never leaves is ungoverned while looking like work in progress.
- Enforcement is a management group move: one operation, auditable, and
  reversible by moving back. That's the main advantage over editing assignments
  in place.
- Because `DoNotEnforce` writes no activity log entries, the audit period
  produces no record of what would have been blocked. If that evidence is
  needed, for example to make the case to a workload team, it has to be
  reconstructed from compliance state at a point in time rather than from logs.
