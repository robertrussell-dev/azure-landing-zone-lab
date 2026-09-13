# Runbook: deploy and destroy the landing zone

The READMEs describe what each directory does. This is the order you actually
run them in, including the two places where you have to go back and re-run
something, and what happens when you try to take it all down again.

Both implementations are covered. **Deploy one or the other, never both.** They
build the same management groups with the same names. The Bicep role
assignments also get a different GUID for a name than the ones Terraform
created, so a second deployment on top of the first fails partway through with
`RoleAssignmentExists`. A what-if showed this; details are in
[bicep/README.md](../bicep/README.md#what-if-against-the-deployed-estate).

## 1. Before you start

### Tooling

| Tool | Version | Why that one |
|---|---|---|
| Terraform | `>= 1.9.0`, CI pins `1.16.1` | `required_version` in every root |
| azurerm provider | `~> 5.4` | pinned, and `.terraform.lock.hcl` is committed |
| azapi provider | `~> 2.12` | `00` and `20` only, for what azurerm has no resource for or can only do one subscription at a time |
| Bicep CLI | `v0.47.16` | pinned in [scripts/install-bicep.sh](../scripts/install-bicep.sh) |
| Azure CLI | any recent | only used to sign in and to deploy Bicep |

**The Azure CLI carries its own, usually older, Bicep**, which skips validating
newer resource types with only a `BCP081` warning. Update it once:

```bash
az bicep install --version v0.47.16
az bicep version
```

### Access

Sign in and confirm you are in the right tenant before anything else. Nothing
in either tree pins the tenant for you on the Bicep side.

```bash
az login
az account show --query "{tenant:tenantId, sub:name}" -o table
```

What each stage needs:

| Stage | Terraform | Bicep |
|---|---|---|
| `00-management-groups` | management group, hierarchy settings and role definition write at the tenant root group | deployment rights on a management group, plus the same writes at the tenant root group |
| `10-policy` | Owner at the intermediate root | same |
| `20-subscription-placement` | Owner at the intermediate root, plus billing scope rights to vend | **Owner or Contributor at `/`** |
| `25-brownfield-seed` | Contributor on the adopted subscription | same |
| `30-auto-delete` | Contributor on `sub-management`, plus role definition and role assignment writes at the intermediate root | the same, plus **Azure Deployment Stack Owner** at Platform Management, because a stack with deny settings needs it |
| `90-optional-network` | Contributor on `sub-connectivity` | same |

The Bicep row for `20` is the hard one. `Microsoft.Subscription/aliases` is
tenant only, so that root needs a built in role at `/`. `00` avoids this by
running at management group scope; see
[bicep/README.md](../bicep/README.md#scope-replaces-the-provider).

**Billing scope permissions are a separate model from Azure RBAC.** Owner on a
management group grants nothing there. See section 4 of
[onboard-application-landing-zone.md](onboard-application-landing-zone.md).

## 2. Deploy with Terraform

Seven stages, the last three optional. Stages 2 and 4 are the same directory
run twice. That isn't a mistake, see 2.4.

### 2.1 Management groups

```bash
cd terraform/00-management-groups
cp terraform.tfvars.example terraform.tfvars   # tenant, subscription, prefix
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Always `plan -out` and apply the saved plan. It guards against a `.tf` file
changing between reading the plan and typing yes.

The prefix becomes part of every management group ID and can't be changed
afterward without recreating the hierarchy. Choose it once.

Verify:

```bash
az account management-group list --query "length([?starts_with(name,'contoso')])" -o tsv
```

Thirteen. Filter on the prefix rather than counting the whole list, which also
returns the tenant root group and so answers 14.

This stage also changes two tenant wide settings on the tenant root group. New
subscriptions land in `contoso-sandboxes` unless something places them, and
creating management groups needs write permission on the tenant root group,
where by default any user can. It also defines a narrow `contoso hierarchy
deployer` role without assigning it to anyone.

### 2.2 Policy, first pass

```bash
cd ../10-policy
cp terraform.tfvars.example terraform.tfvars   # same prefix as 00
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

Leave `log_analytics_workspace_id` commented out. The two assignments that
send logs to the workspace are skipped until it exists. Set `alert_emails` and
the Service Health one goes in now, so six of the eight; leave it empty and
it's five.

The `DenyAction` assignment at Platform goes in on this pass, before the
workspace exists. It only refuses deletes, so it doesn't get in the way of
creating anything.

### 2.3 Subscription placement

This directory does three separable things, and how you sequence them depends
on whether you are vending subscriptions at all.

**Placement and budgets only** (`create_subscriptions = false`): everything
works in one pass. Verified: the plan is clean with `management_subscription_id`
left unset.

```bash
cd ../20-subscription-placement
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

**Vending as well** (`create_subscriptions = true`, `billing_scope_id` filled
in): this is two applies, and **the plan won't warn you.**

The central workspace is created through an aliased provider pointed at
`management_subscription_id`, which doesn't exist until the apply that vends
it, and `terraform plan` succeeds with it unset.

1. Apply with `create_subscriptions = true`. Every subscription marked
   `vend = true` in `subscriptions.tf` gets vended and placed. The rest stay in
   the map without being created, so flip one to `true` when you want it.
2. Read the new management subscription's GUID:
   `az account list --all --query "[?name=='sub-management'].id" -o tsv`
3. Put it in `terraform.tfvars` as `management_subscription_id`.
4. Apply again. This creates `rg-management-logs` and the workspace.

### 2.4 Policy, second pass

Now the workspace exists, so the two assignments that send logs to it can be
made.

`20-subscription-placement` has no output for it, so read the ID off Azure:

```bash
az monitor log-analytics workspace show \
  --subscription <management GUID> \
  --resource-group rg-management-logs \
  --workspace-name law-contoso-management \
  --query id -o tsv
```

Put that in `terraform/10-policy/terraform.tfvars` as
`log_analytics_workspace_id`, then:

```bash
cd ../10-policy
terraform plan -out=tfplan && terraform apply tfplan
```

Verify all eight: `az policy assignment list --disable-scope-strict-match -o table`,
or read the compliance blade.

**Remediate the subscriptions that already exist.** DeployIfNotExists only acts
on something created or updated after it's assigned, so the activity log and
Service Health assignments do nothing for the subscriptions already vended
until they're remediated. Scan each subscription, wait for the scans to finish,
then remediate at the intermediate root:

```bash
az policy state trigger-scan --subscription <GUID>   # once per subscription

MG=/providers/Microsoft.Management/managementGroups/contoso
az policy remediation create --management-group contoso --name remediate-activity-log \
  --policy-assignment $MG/providers/Microsoft.Authorization/policyAssignments/dine-activity-log
az policy remediation create --management-group contoso --name remediate-service-health \
  --policy-assignment $MG/providers/Microsoft.Authorization/policyAssignments/dine-service-health
```

A remediation only fixes what the last scan found, so a subscription whose scan
hadn't finished needs a second one. The scan also needs `Microsoft.PolicyInsights`
registered in the subscription; vending's baseline does that, and a
subscription with it missing fails the scan with a message saying so.

Subscriptions vended from now on don't need any of this. They're evaluated
when they're created, and remediated automatically.

### 2.5 Brownfield seed, optional

Only if you want the audit only archetype to have something to report. An
empty subscription produces no compliance state.

```bash
cd ../25-brownfield-seed
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

Everything it creates is free. Read the header of `main.tf` before assuming the
non-compliance is a bug.

### 2.6 Auto delete janitor, optional, and first if you'll switch anything on

Deploy this before you turn on any billable flag in 2.7, since it's what
deletes a device you forget about.

```bash
cd ../30-auto-delete
cp terraform.tfvars.example terraform.tfvars   # tenant, subscriptions, prefix
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

Free. The account, runbook and schedule bill nothing to exist, and a run every
two hours stays inside Automation's 500 free job minutes a month.

Check it can see what it needs to before trusting it. The `dry_run_command`
output starts one run that reports what it would delete and deletes nothing:

```bash
terraform output -raw dry_run_command | sh
```

With nothing billable switched on, the job output reads `Nothing expired.` The
same check works from a workstation against your own login, reporting only:

```powershell
./automation/Remove-ExpiredResources.ps1 -ManagementGroupId contoso -DryRun $true
```

The janitor deletes only what carries both `autoDelete = "true"` and a
`deleteAfter` time that has passed, and only the six device types its role
lists. The header of
[Remove-ExpiredResources.ps1](../automation/Remove-ExpiredResources.ps1)
explains all three guards.

### 2.7 Hub and spoke network, optional and the only thing here that costs real money

Free by default. The hub and spoke virtual networks, every subnet in
[docs/ip-plan.md](../docs/ip-plan.md), the peerings, network security groups and
route tables bill nothing at rest, so this can be applied and left.

```bash
cd ../90-optional-network
cp terraform.tfvars.example terraform.tfvars   # connectivity subscription GUID
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

Check the plan's `standing_monthly_cost_usd` output before applying. With every
flag false it reads 0 and the note says so.

Run it after `10-policy`. Seven of its subnets are exempted from the subnet
audit assignment, and an exemption needs the assignment to exist. Nothing needs
registering by hand either: the provider registers `Microsoft.Network` in the
connectivity subscription itself.

**Turning anything on.** Each device has its own flag and each flag names its
price; the table is also in the
[hub and spoke diagram](../docs/diagrams/hub-spoke-network.svg). All five plus
their public IPs is 1,495 a month.

```bash
terraform apply -var deploy_firewall=true -auto-approve=false
# ... do the thing you needed the firewall for, capture it ...
terraform apply -var deploy_firewall=false
```

Turning a flag back off destroys that device and leaves the free layer intact.
The route tables always exist, so the firewall flag only adds or removes
routes.

**If you don't turn it off, the janitor will.** Each device is created with a
`deleteAfter` tag `billable_ttl_hours` out, eight by default. Once that passes,
the next run deletes the device, and the run after that deletes its public IP.
Need longer? Pass `-var billable_ttl_hours=24` when you switch the device on.
The tag is written once at creation, so changing the variable later doesn't
move it. If the janitor got there first, the next plain `terraform apply` finds
the device gone and tidies state. Applying with the flag still on recreates it
with a fresh window.

**The gateways are slow.** A VPN or ExpressRoute gateway takes 30 to 45 minutes
to create and about as long to destroy. Budget for that before planning a same
day teardown around one.

## 3. Deploy with Bicep

Same seven stages. Different commands, and a different scope for each one, which
is the part that doesn't carry across. The map is in
[docs/diagrams/bicep-deployment-scopes.svg](../docs/diagrams/bicep-deployment-scopes.svg).

Copy each `main.example.bicepparam` to `main.bicepparam` first.

```bash
# 3.1 management groups, at the tenant root management group
MG=$(az account show --query tenantId -o tsv)
az deployment mg what-if --management-group-id "$MG" --location westus2 \
  --template-file bicep/00-management-groups/main.bicep \
  --parameters bicep/00-management-groups/main.bicepparam
# then swap what-if for create

# 3.2 policy, first pass, at the intermediate root
az deployment mg create --management-group-id contoso --location westus2 \
  --template-file bicep/10-policy/main.bicep \
  --parameters bicep/10-policy/main.bicepparam

# 3.3 subscription placement, at the tenant
az deployment tenant create --location westus2 \
  --template-file bicep/20-subscription-placement/main.bicep \
  --parameters bicep/20-subscription-placement/main.bicepparam

# 3.4 policy, second pass, with logAnalyticsWorkspaceId now filled in
az deployment mg create --management-group-id contoso --location westus2 \
  --template-file bicep/10-policy/main.bicep \
  --parameters bicep/10-policy/main.bicepparam

# 3.5 brownfield seed, at the adopted subscription
az deployment sub create --subscription <brownfield GUID> --location westus2 \
  --template-file bicep/25-brownfield-seed/main.bicep \
  --parameters bicep/25-brownfield-seed/main.bicepparam

# 3.6 auto delete janitor. Two stacks, not deployments; see below.
az stack mg create --name auto-delete --management-group-id contoso-platform-management \
  --deployment-subscription <management GUID> --location westus2 \
  --template-file bicep/30-auto-delete/main.bicep \
  --parameters bicep/30-auto-delete/main.bicepparam \
  --action-on-unmanage deleteAll --deny-settings-mode denyDelete
PRINCIPAL=$(az stack mg show --name auto-delete --management-group-id contoso-platform-management \
  --query outputs.janitorPrincipalId.value -o tsv)
az stack mg create --name auto-delete-role --management-group-id contoso --location westus2 \
  --template-file bicep/30-auto-delete/role.bicep \
  --parameters bicep/30-auto-delete/role.bicepparam --parameters janitorPrincipalId=$PRINCIPAL \
  --action-on-unmanage deleteAll --deny-settings-mode none

# 3.7 hub and spoke, at the connectivity subscription. Free unless a flag is on.
az deployment sub create --subscription <connectivity GUID> --location westus2 \
  --template-file bicep/90-optional-network/main.bicep \
  --parameters bicep/90-optional-network/main.bicepparam
```

**3.6 is the one stage that isn't `az deployment`.** The janitor is deployed as
two deployment stacks, so that a deny assignment protects the Automation account
from being deleted by anyone, you included, except through the stack. There's
no what-if for a stack. The nearest checks are `az stack mg validate` with the
same arguments, which is what found both of the scope rules in ADR 0008, and an
ordinary `az deployment mg what-if` of `main.bicep`. The runbook's content comes
from the URL in `main.bicepparam`, so pin it to the commit you reviewed.

**Run what-if before create**, and keep the two adjacent: unlike a saved plan,
nothing stops the file changing in between.

Vending is a single deployment here rather than two applies, because Bicep can
pass a runtime subscription ID across a nested deployment boundary. The
workspace still needs `managementSubscriptionId`, so 3.3 is still two runs if
you are vending from scratch.

After 3.4, remediate the existing subscriptions exactly as in 2.4. A
subscription the Bicep tree vended won't have `Microsoft.PolicyInsights`
registered, because no template declares it, so register it before the scan:

```bash
az provider register --namespace Microsoft.PolicyInsights --subscription <GUID>
```

## 4. Destroy the Terraform tree

Reverse order. Nothing in the deployed set bills more than trivial amounts, so
this is hygiene rather than cost.

```bash
cd terraform/90-optional-network     && terraform destroy
cd ../30-auto-delete                 && terraform destroy
cd ../25-brownfield-seed             && terraform destroy
cd ../10-policy                      && terraform destroy -target=module.deny_platform_workspace_delete
cd ../20-subscription-placement      && terraform destroy
cd ../10-policy                      && terraform destroy
cd ../00-management-groups           && terraform destroy
```

The fourth line is out of order because the `DenyAction` assignment would
otherwise fail the destroy of `20` with a 403 naming `deny-platform-delete`. The
lock on `rg-management-logs` is managed in `20`, and Terraform removes it before
the group.

If anything billable is on, turn it off first. Setting the flags back to false
is faster than a full destroy:

```bash
cd terraform/90-optional-network
terraform apply -var deploy_firewall=false -var deploy_bastion=false \
  -var deploy_vpn_gateway=false -var deploy_expressroute_gateway=false \
  -var deploy_route_server=false
```

### What destroying leaves behind

**Anything policy deployed.** The two baseline assignments create resources in
every subscription that Terraform never created and so never destroys. Removing
the assignments leaves them in place:

```bash
# once per subscription
az group delete --name rg-service-health-alerts --subscription <GUID> --yes
az monitor diagnostic-settings subscription delete --name subscriptionToLa \
  --subscription <GUID> --yes
```

**Defender for Cloud stays on its free tier.** The `CloudPosture` plan can't be
deleted, so destroying the baseline leaves it at `Free`, which costs nothing.
Defender's own benchmark assignment at each subscription stays too.

**The hierarchy settings go back to the defaults** when `00` is destroyed: new
subscriptions land under the tenant root again, and anyone can create
management groups.

### `terraform destroy` on 20 will fail, by design

If you vended subscriptions, the destroy of `20` fails at plan time:

```
Error: Instance cannot be destroyed
  Resource module.subscription["management"].azurerm_subscription.this has
  lifecycle.prevent_destroy set
```

Destroying `azurerm_subscription` cancels the subscription, so it's guarded.
Decide what you want:

**Keep the subscriptions, drop everything else.** Take them out of state first.
They stay alive in Azure and Terraform stops managing them.

```bash
terraform state rm 'module.subscription["management"]'
terraform state rm 'module.subscription["online-portal-prod"]'
terraform destroy
```

**Cancel a subscription.** Do it outside Terraform, from the portal or with
`az account subscription cancel` from the `account` extension. It's
recoverable for a limited window, during which `Decommissioned` holds it.

### Management groups won't delete while they contain anything

Azure requires a management group to have no child groups and no subscriptions
before it can be deleted. Terraform's own dependency graph handles the ordering
within `00`, but if a subscription is still associated the destroy fails. Detach
it first:

```bash
az account management-group subscription remove \
  --name contoso-lz-corp-audit --subscription <GUID>
```

## 5. Destroy the Bicep tree

There's no `bicep destroy`. Complete mode is
[resource group scoped only](https://learn.microsoft.com/azure/azure-resource-manager/templates/deployment-modes)
and being deprecated;
[deployment stacks](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks)
are the supported answer, and only `30-auto-delete` uses them. ADR 0008 says
why the rest don't.

So apart from the janitor it's manual, in the same reverse order:

```bash
# 5.0 the janitor: its two stacks, role first. The only real destroy in this tree.
az stack mg delete --name auto-delete-role --management-group-id contoso \
  --action-on-unmanage deleteAll --yes
az stack mg delete --name auto-delete --management-group-id contoso-platform-management \
  --action-on-unmanage deleteAll --yes

# 5.1 the hub and spoke, including anything billable inside it
az group delete --name rg-hub-network --subscription <connectivity GUID> --yes

# 5.2 the seeded network
az group delete --name rg-legacy-app --subscription <brownfield GUID> --yes

# 5.3 the central workspace. The lock first, or the group delete is refused.
az lock delete --name lock-management-logs --resource-group rg-management-logs \
  --subscription <management GUID>
az group delete --name rg-management-logs --subscription <management GUID> --yes

# 5.4 budgets
az consumption budget delete --budget-name budget-demo --subscription <GUID>

# 5.5 policy assignments, and the role assignments their identities hold
az policy assignment delete --name append-costcenter \
  --scope /providers/Microsoft.Management/managementGroups/contoso
# repeat for audit-subnet-nsg, deny-nic-public-ip (twice, two scopes),
# deny-platform-delete (at contoso-platform), dine-nsg-diagnostics,
# dine-activity-log and dine-service-health, then clear up what the last two
# deployed: see "What destroying leaves behind" in section 4

# 5.6 the tenant root settings and the custom role
az account management-group hierarchy-settings delete --name <tenant ID>
az role definition delete --name "contoso hierarchy deployer" \
  --scope /providers/Microsoft.Management/managementGroups/<tenant ID>

# 5.7 management groups, deepest first
az account management-group delete --name contoso-lz-corp-audit
# ... then the rest of tier 2, then tier 1, then contoso
```

**5.3 works with `deny-platform-delete` still assigned**, because the built in
`DenyAction` definition doesn't block a resource group delete. The lock covers
that path, so removing it is what opens it. ADR 0008 has the detail.

**`az policy assignment` commands can fail at management group scope** with
`MissingSubscription: The request did not have a subscription or a valid tenant
level resource provider`. That's a CLI quirk, not permissions. Use the API:

```bash
az rest --method delete --url "https://management.azure.com/providers/Microsoft.Management/managementGroups/contoso/providers/Microsoft.Authorization/policyAssignments/append-costcenter?api-version=2025-03-01"
```

**Deleting an assignment doesn't remove the role assignments its managed
identity holds.** Terraform tracks those in state and removes them; here you
have to find and delete them yourself:

```bash
az rest --method get --url "https://management.azure.com/providers/Microsoft.Management/managementGroups/contoso/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=atScope()"
```

Anything with `principalType: ServicePrincipal` pointing at a principal that no
longer exists is an orphan left by a deleted assignment.

## 6. What cannot be destroyed

**Subscriptions.** They cancel, they don't delete. A canceled subscription
stays visible for a retention window, which is what `Decommissioned` is for.

**The alias object.** `Microsoft.Subscription/aliases` creates a subscription
and can't update one; Microsoft's documentation is explicit that property
changes made through it aren't retained. Renaming a subscription is a separate
Rename operation.

**The tenant root group.** Not managed by this repository and not deletable.
`contoso` hangs off it, and removing `contoso` leaves the tenant as it was.

**Resource provider registrations.** A provider can only be unregistered once
nothing in the subscription uses it, and a registration costs nothing, so they
stay.

## Quick reference

| I want to | Terraform | Bicep |
|---|---|---|
| Preview | `terraform plan -out=tfplan` | `az deployment <scope> what-if` |
| Apply a reviewed preview | `terraform apply tfplan` | not possible, re-runs the template |
| See what exists | `terraform state list` | `az deployment <scope> list` |
| Detect drift | `terraform plan` | `what-if`, when you run it |
| Remove everything | `terraform destroy`, reverse order | by hand, reverse order |
| Stop managing without deleting | `terraform state rm <addr>` | stop deploying the file |
