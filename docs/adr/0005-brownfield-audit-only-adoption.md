# ADR 0005: Brownfield adoption through an audit only duplicate hierarchy

Status: Accepted
Date: 2026-09-06

## Context

Most landing zone engagements are not greenfield. Subscriptions already exist,
they run production workloads, and the teams that own them did not ask for a
governance programme. Applying an enforcing policy set to those subscriptions
on day one is how a platform team becomes the reason a release failed.

The problem is that policy compliance cannot be assessed without assigning the
policy, and assigning the policy is what creates the risk.

## Decision

**Duplicate the archetype management group and its policy assignments, with
`enforcementMode` set to `DoNotEnforce`, and place adopted subscriptions there
first.**

This is deployed, not described. `Corp (audit only)`
(`contoso-lz-corp-audit`) carries the same Deny assignment as `Corp`, with
enforcement off. `DemoSubscription`, which predates the landing zone, sits
under it.

Moving that one management group association from `contoso-lz-corp-audit` to
`contoso-lz-corp` is the entire change required to enforce. No policy is
rewritten, no assignment is edited, and the policy set the subscription was
measured against is the policy set that begins enforcing.

Microsoft notes this approach carries no additional cost, because it duplicates
the management group hierarchy and the assignments, not the workloads. That is
correct: a parallel hierarchy does not imply parallel spend.

## What DoNotEnforce actually does

Worth being precise, because the portal and the API use different words for the
same setting and it causes confusion.

| Portal label | JSON value | Effect enforced | Activity log entry |
|---|---|---|---|
| Enabled | `Default` | Yes | Yes |
| Disabled | `DoNotEnforce` | No | **No** |
| Enroll | `Enroll` | Only for enrolled scopes | For enrolled resources |

`Disabled` in the portal is `DoNotEnforce` in JSON. They are one mode, not two
options.

Two consequences that matter operationally:

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
required state" and does not define that. This is the part the platform team
has to decide, so it is decided here.

Enforcement is turned on when all of the following hold:

1. **Zero non-compliant resources against the Deny policies.** Deny is the only
   effect that can break a deployment, so it is the only one that must be at
   zero. A Deny does not remove existing violations, it makes them
   undeployable, so a single remaining violation becomes a failed release at
   an unpredictable future date rather than a problem discovered now.
2. **Audit findings triaged, not necessarily fixed.** Every non-compliant
   resource against an Audit effect has either a remediation date or a
   `Waiver` exemption with an expiry. Unreviewed findings are the failure mode,
   not unfixed ones.
3. **DeployIfNotExists remediated during the audit period**, not deferred to
   after the move. Remediation works under `DoNotEnforce`, so deferring it is a
   choice rather than a constraint.
4. **One full change cycle observed.** At least one real deployment by the
   workload team has occurred while the audit assignment was in place, and its
   resources evaluated compliant. Compliance measured on a static estate proves
   the resources are fine. It does not prove the team's pipeline produces
   compliant resources, and the pipeline is what will hit the Deny.

Point four is the one most likely to be skipped, and it delays every adoption
by roughly a sprint. That delay is accepted deliberately: it is the only one of
the four that tests the thing that will actually break, which is the team's
pipeline rather than the resources sitting in the subscription.

## Alternatives considered

Microsoft's brownfield article describes the duplicate hierarchy approach and
does not mention the two below. Both are newer and both are lighter.

**`Enroll` enforcement mode.** A single assignment on the real archetype, in
`Enroll` mode. Scopes without an enrollment resource behave as though the
assignment were `DoNotEnforce`; enforcement begins for a scope when its owner
creates an enrollment. This achieves staged enforcement **without duplicating
the hierarchy at all**, and moves the decision to the scope owner rather than
requiring a subscription move by the platform team.

Not chosen here for one reason: the duplicate hierarchy makes the state visible
in the portal tree. Anyone can see which subscriptions are being assessed and
which are governed, without querying enrollment resources. At this size that
legibility is worth more than the saved management groups.

The trade reverses at some number of in flight subscriptions, beyond which the
duplicated groups cost more than the visibility is worth. That number is not
established here, and asserting one would be inventing it. What is clear is
that the review should be triggered by adoptions running concurrently rather
than by the size of the estate.

**Resource selectors for gradual rollout.** An assignment can carry
`resourceSelectors` that narrow evaluation by resource location or type, so
enforcement is rolled out region by region rather than subscription by
subscription. This composes with either approach and is the right tool when the
risk is concentrated in a resource type rather than in a team.

**Assign enforcing policy directly and handle the breakage.** Rejected. This is
what happens by default when nobody makes a decision. The cost is not
technical: the platform team's first interaction with every workload team
becomes a broken deployment, and governance adoption is a political problem
long before it is an engineering one.

## Consequences

- The hierarchy carries a management group per archetype under adoption. With
  three archetypes that is manageable. With many, this approach does not scale
  and `Enroll` mode should be revisited.
- The audit only group is not a permanent home. **Ninety days is the limit.** A
  subscription still there after that triggers a review and escalation rather
  than another month of assessment, because a subscription that never leaves
  has quietly become ungoverned while appearing to be in progress.
- Enforcement is a management group move, which means it is one operation, it
  is auditable, and it is reversible by moving back. That reversibility is the
  main practical argument for this approach over editing assignments in place.
- Because `DoNotEnforce` writes no activity log entries, the audit period
  produces no record of what would have been blocked. If that evidence is
  needed, for example to make the case to a workload team, it has to be
  reconstructed from compliance state at a point in time rather than from logs.
