# Runbook: onboard an application landing zone

Subscription vending. What the workload team supplies, what the platform team
decides, and the steps to provision.

This is written from having run it. The two sections at the end record failures
that are easy to hit and hard to diagnose.

## 1. What the workload team supplies

Requested before anything is provisioned. A request missing any of these goes
back rather than forward, because every one of them changes a platform decision
that is expensive to reverse.

| Input | Why the platform team needs it |
|---|---|
| Hybrid connectivity required | Decides Corp versus Online. This is the archetype decision and it determines the policy set the workload inherits. See ADR 0003. |
| Expected address space, and growth over 24 months | Address space cannot be resized without recreating the virtual network. Ask for the 24 month figure, not today's. |
| Environments needed | Each becomes its own subscription in the same archetype management group, not its own management group. See ADR 0002. |
| Criticality and data classification | Drives whether extra archetypes apply, for example a PCI management group, and what the backup and retention expectations are. |
| Internet ingress required | Not the same question as the archetype. A public facing application can sit under Corp if it also needs hybrid routing. |
| Owning team, and an on call contact | Becomes the subscription owner and the budget alert recipient. |

Note what is **not** asked: which region, or how big the virtual machines are.
Subscriptions are not regional, and sizing is the workload team's business.

## 2. What the platform team decides

| Decision | Owner | Notes |
|---|---|---|
| Management group placement | Platform | Applies the ADR 0003 rule to the connectivity answer. |
| Address space allocation | Platform | From the platform supernet. Never delegated, because overlapping ranges are discovered at peering time, which is far too late. |
| Subscription name | Platform | Follows the naming convention. The alias is immutable, so this is decided once. |
| Budget amount and alert thresholds | Platform, with the team | Actual and forecast. The forecast threshold is the useful one. |
| Policy exemptions, if any | Platform | Waiver category, with an expiry. An exemption renewed twice is a policy defect, not a resource defect. |

## 3. Steps

1. **Confirm the archetype.** Apply the ADR 0003 decision rule to the
   connectivity answer. If the workload needs to reach on premises through the
   hub, it is Corp. If not, it is Online. Do not decide this from whether the
   application is internet facing.

2. **Allocate address space** from the platform supernet and record it before
   provisioning. The allocation is the platform's record, not the workload
   team's.

3. **Create the subscription.** In `infra/20-subscription-placement`, add the
   subscription with its billing scope, then plan and apply. Subscriptions
   created through the alias API land in the tenant root management group.

4. **Place the subscription** into the archetype management group. This is a
   separate operation from creation, always.

5. **Apply the budget.** Actual at 80 percent, forecast at 100 percent, with
   the on call contact as recipient.

6. **Assign subscription ownership** to the workload team at subscription
   scope. Do not grant them rights at management group scope. Microsoft's
   guidance is explicit that application teams should be granted at
   subscription or resource group scope, because management group grants
   over permission through inheritance.

7. **Verify inherited policy.** Confirm the subscription shows the expected
   assignments and wait for the first compliance scan before handing over. A
   scan can take up to 30 minutes.

8. **Hand over** with the address allocation, the archetype and its policy
   implications, and the budget thresholds.

### Brownfield variant

A subscription being adopted from an existing estate is placed under the audit
only duplicate of its archetype first, not the archetype itself. It is
evaluated against the target policy set with `enforcementMode` set to
`DoNotEnforce`, so nothing is blocked while compliance is assessed. Moving the
management group association to the real archetype is what turns enforcement
on. See ADR 0005.

## 4. Billing scope permissions are a separate model

This is the most common blocker and it does not look like a permissions problem
when you hit it.

Creating a subscription requires permission at the **billing scope**, which is
a different system from Azure RBAC. Owner on the tenant root management group
grants nothing here. Global Administrator grants nothing here.

The required role is one of:

- Owner or Contributor on the invoice section, billing profile, or billing
  account
- Azure subscription creator on the invoice section

Check what you hold before planning the work:

```bash
az rest --method get \
  --url "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/{billingAccountName}/billingRoleAssignments?api-version=2024-04-01"
```

The billing scope for a subscription alias has this shape, and all three
segments are required:

```
/providers/Microsoft.Billing/billingAccounts/{billingAccountName}
  /billingProfiles/{billingProfileName}
  /invoiceSections/{invoiceSectionName}
```

Also register the resource provider first. It is not registered by default in a
new tenant, and the failure it produces does not mention registration:

```bash
az provider register --namespace Microsoft.Subscription
```

## 5. A new subscription is not immediately writable

After the subscription is created, the creator is granted Owner on it. That
role assignment appears in the assignment store within seconds, and Azure
Resource Manager will still refuse writes for some minutes afterwards:

```
AuthorizationFailed: The client '...' does not have authorization to perform
action 'Microsoft.Resources/subscriptions/resourcegroups/write' ...
If access was recently granted, please refresh your credentials.
```

The role assignment is genuinely there. `az role assignment list` on the new
subscription shows Owner. The failure is authorization cache propagation plus a
cached access token, and the last sentence of the error is the real
instruction rather than boilerplate.

What to do, in order:

1. `az account list --refresh` so the CLI knows the subscription exists at all.
   Until this runs, commands against it fail with "subscription not found",
   which looks like a different problem entirely.
2. `az login` to obtain a token issued after the role assignment.
3. Retry.

The practical consequence for automation: **creating a subscription and
configuring it are not one atomic operation.** A pipeline that creates a
subscription and immediately deploys into it will fail intermittently.

Terraform makes this worse in a specific way. When a create fails partway, the
resource is marked tainted, and the next plan proposes replacing it. For a
subscription, replacement means cancellation. This is why
`azurerm_subscription` in this repository carries `prevent_destroy`, and why
recovering from a partial create is `terraform untaint` rather than a rerun.
