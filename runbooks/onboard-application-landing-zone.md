# Runbook: onboard an application landing zone

Subscription vending. What the workload team supplies, what the platform team
decides, and the steps to provision.

This is written from having run it. The two sections at the end record failures
that are easy to hit and hard to diagnose.

## 1. What the workload team supplies

Requested before anything is provisioned. A request missing any of these goes
back, because each one feeds a platform decision that's expensive to reverse.

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

3. **Create the subscription.** In `terraform/20-subscription-placement`, add the
   subscription with its billing scope, then plan and apply. Subscriptions
   created through the alias API land in the tenant root management group.

4. **Place the subscription** into the archetype management group. This is a
   separate operation from creation, always.

5. **Register the resource providers** the workload needs. A newly created
   subscription has almost none registered, and the failure is a 409 that names
   the namespace rather than the cause:

   ```
   MissingSubscriptionRegistration: The subscription is not registered to use
   namespace 'Microsoft.OperationalInsights'
   ```

   ```bash
   az provider register --namespace Microsoft.OperationalInsights --subscription <id>
   ```

   Registration is asynchronous and takes a few minutes per namespace. Do it as
   part of vending rather than leaving the first deployment to discover it.

   **Register `Microsoft.PolicyInsights` even though no deployment asks for
   it.** Without it the subscription reports no compliance records at all.
   Nothing fails, and it looks like a scan that hasn't run yet, which is an easy
   hour to lose. The error only shows if you trigger a scan:

   ```bash
   az provider register --namespace Microsoft.PolicyInsights --subscription <id>
   az policy state trigger-scan --subscription <id>
   ```

6. **Apply the budget.** Actual at 80 percent, forecast at 100 percent, with
   the on call contact as recipient.

7. **Assign subscription ownership** to the workload team at subscription
   scope. Do not grant them rights at management group scope. Microsoft's
   guidance is explicit that application teams should be granted at
   subscription or resource group scope, because management group grants
   over permission through inheritance.

8. **Verify inherited policy.** Confirm the subscription shows the expected
   assignments, and confirm compliance records actually exist rather than
   assuming a slow scan. Zero records usually means `Microsoft.PolicyInsights`
   is unregistered, not that evaluation is pending. A genuine first scan can
   still take up to 30 minutes.

9. **Hand over** with the address allocation, the archetype and its policy
   implications, and the budget thresholds.

### Brownfield variant

A subscription being adopted from an existing estate is placed under the audit
only duplicate of its archetype first, not the archetype itself. It is
evaluated against the target policy set with `enforcementMode` set to
`DoNotEnforce`, so nothing is blocked while compliance is assessed. Moving the
management group association to the real archetype is what turns enforcement
on. See ADR 0005.

## 4. Billing scope permissions are a separate model

This is the most common blocker, and it doesn't look like a permissions
problem when you hit it.

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

## 5. Azure Pipelines will not run until the organization has billing

A new Azure DevOps organization gets **zero** Microsoft hosted parallel jobs.
Microsoft made that change to stop free CI compute being used for crypto
mining, and it applies to private projects as well as public ones.

The symptom is not an error. The run queues against the hosted pool, reports
`notStarted`, has no validation results, and never begins. Nothing fails and
nothing explains why.

The fix is to link the organization to an Azure subscription under
**Organization settings, Billing**. The free grant is applied automatically
once billing is configured: one parallel job, sixty minutes per run, 1,800
minutes a month for private projects. Linking associates billing identity only
and deploys nothing into the subscription.

There is also a request form at `aka.ms/azpipelines-parallelism-request`, which
takes several business days. It is only worth using if billing linkage is not
available.

A queued run picks up on its own once the grant lands, so there is no need to
cancel and requeue.

## 6. A new subscription is not immediately writable

After the subscription is created, the creator is granted Owner on it. That
role assignment appears in the assignment store within seconds, and Azure
Resource Manager refuses every write to the subscription anyway:

```
AuthorizationFailed: The client '...' does not have authorization to perform
action 'Microsoft.Resources/subscriptions/resourcegroups/write' ...
If access was recently granted, please refresh your credentials.
```

The role assignment is there. `az role assignment list` shows Owner
at subscription scope, and the portal shows the same. The error's closing
sentence about refreshing credentials is misleading: refreshing them does not
help, and neither does waiting.

What to do, in order:

1. `az account list --refresh` so the CLI knows the subscription exists at all.
   Until this runs, commands against it fail with "subscription not found",
   which looks like a different problem entirely.
2. `az login` to obtain a token issued after the role assignment.
3. **Place the subscription in the management group hierarchy, then retry.**

Step 3 is the one that works. I saw the refusal last over forty minutes, well
past normal propagation, and a fresh `az login` didn't change it. The portal
agreed, leaving the subscription out of the Create Resource Group picker while
showing me as Owner elsewhere. Moving the subscription under a management group
where I held Owner fixed it immediately.

```bash
az account management-group subscription add \
  --name <management-group> --subscription <id>
```

So **place the subscription before deploying into it.** For automation, that
means creating a subscription and configuring it aren't one atomic operation,
and a pipeline that deploys straight after creating will fail intermittently.

Terraform makes this worse. When a create fails partway, the resource is marked
tainted and the next plan proposes replacing it, which for a subscription means
cancellation. That's why `azurerm_subscription` here has `prevent_destroy`, and
why recovering from a partial create is `terraform untaint`, not a rerun.
