# Runbook: deploy and destroy the landing zone

The READMEs describe what each directory does. This is the order you actually
run them in, including the two places where you have to go back and re-run
something, and what happens when you try to take it all down again.

Both implementations are covered. **Deploy one or the other, never both.** They
build the same management groups with the same names. The Bicep role
assignments also get a different GUID for a name than the ones Terraform
created, so a second deployment on top of the first fails partway through with
`RoleAssignmentExists`. That isn't a hypothetical: it came out of
a what-if, and the detail is in
[bicep/README.md](../bicep/README.md#what-if-against-the-deployed-estate).

## 1. Before you start

### Tooling

| Tool | Version | Why that one |
|---|---|---|
| Terraform | `>= 1.9.0`, CI pins `1.16.1` | `required_version` in every root |
| azurerm provider | `~> 5.4` | pinned, and `.terraform.lock.hcl` is committed |
| Bicep CLI | `v0.47.16` | pinned in [scripts/install-bicep.sh](../scripts/install-bicep.sh) |
| Azure CLI | any recent | only used to sign in and to deploy Bicep |

**The Azure CLI carries its own Bicep and it's usually older.** Resource type
schemas ship inside the compiler, so an older copy silently stops validating
newer types: `az deployment` against a CLI holding 0.39.26 emits `BCP081` for
`Microsoft.Network/virtualNetworks@2025-09-01` and deploys it unchecked. Fix it
once, before you start:

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
| `00-management-groups` | management group write at tenant root | deployment rights on a management group |
| `10-policy` | Owner at the intermediate root | same |
| `20-subscription-placement` | Owner at the intermediate root, plus billing scope rights to vend | **Owner or Contributor at `/`** |
| `25-brownfield-seed` | Contributor on the adopted subscription | same |

The Bicep row for `20` is the one that bites. `Microsoft.Subscription/aliases`
is a tenant-only resource type, so that root is a tenant deployment and needs a
role at root scope `/`, which accepts built-in roles only. `00` deliberately
avoids this by running at management group scope; the reasoning is in
[bicep/README.md](../bicep/README.md#scope-replaces-the-provider).

**Billing scope permissions are a separate model from Azure RBAC.** Owner on a
management group grants nothing there. See section 4 of
[onboard-application-landing-zone.md](onboard-application-landing-zone.md).

## 2. Deploy with Terraform

Five stages, and stages 2 and 4 are the same directory run twice. That isn't a
mistake, see 2.4.

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
afterwards without recreating the hierarchy. Choose it once.

Verify:

```bash
az account management-group list --query "length([?starts_with(name,'contoso')])" -o tsv
```

Thirteen. Filter on the prefix rather than counting the whole list, which also
returns the tenant root group and so answers 14.

### 2.2 Policy, first pass

```bash
cd ../10-policy
cp terraform.tfvars.example terraform.tfvars   # same prefix as 00
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

Leave `log_analytics_workspace_id` commented out. Four of the five assignments
go in. The DeployIfNotExists one is skipped on purpose: with no workspace to
point at it would create an identity, grant it two roles across the hierarchy,
and remediate nothing.

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
it. `terraform plan` succeeds anyway with that variable unset, which was
checked rather than assumed. The apply is where it matters.

1. Apply with `create_subscriptions = true`. The subscriptions get vended and
   placed.
2. Read the new management subscription's GUID:
   `az account list --all --query "[?name=='sub-management'].id" -o tsv`
3. Put it in `terraform.tfvars` as `management_subscription_id`.
4. Apply again. This creates `rg-management-logs` and the workspace.

### 2.4 Policy, second pass

Now the workspace exists, so the fifth assignment can be made.

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

Verify all five: `az policy assignment list --disable-scope-strict-match -o table`,
or read the compliance blade.

### 2.5 Brownfield seed, optional

Only if you want the audit-only archetype to have something to report on. An
empty subscription produces no compliance state at all, which makes the whole
pattern look broken when it's merely inapplicable.

```bash
cd ../25-brownfield-seed
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

Everything it creates is free. Read the header of `main.tf` before assuming the
non-compliance is a bug.

### 2.6 Hub and spoke network, optional and the only thing here that costs real money

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

**Turning anything on.** Each device has its own flag and each flag names its
price. Roughly, per month: firewall 912 on Standard or 288 on Basic, Bastion
212, VPN gateway 139, ExpressRoute gateway 139, Route Server 73. All five plus
their public IPs is 1,495.

```bash
terraform apply -var deploy_firewall=true -auto-approve=false
# ... do the thing you needed the firewall for, capture it ...
terraform apply -var deploy_firewall=false
```

Turning a flag back off destroys that device and leaves the free layer intact.
That is the intended cycle, and it is why the route tables are created empty
rather than conditionally: switching the firewall on adds routes, switching it
off removes them, and nothing restructures.

**The gateways are slow.** A VPN or ExpressRoute gateway takes 30 to 45 minutes
to create and about as long to destroy. Budget for that before planning a same
day teardown around one.

## 3. Deploy with Bicep

Same five stages. Different commands, and a different scope for each one, which
is the part that doesn't carry across. The map is in
[docs/diagrams/bicep-deployment-scopes.svg](../docs/diagrams/bicep-deployment-scopes.svg).

Copy each `main.example.bicepparam` to `main.bicepparam` first; the examples are
real parameter files, so a renamed parameter fails at compile time rather than
at deployment time.

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

# 3.6 hub and spoke, at the connectivity subscription. Free unless a flag is on.
az deployment sub create --subscription <connectivity GUID> --location westus2 \
  --template-file bicep/90-optional-network/main.bicep \
  --parameters bicep/90-optional-network/main.bicepparam
```

**Always what-if before create.** It's the nearest thing to `terraform plan`
and it isn't the same thing: it predicts, it doesn't produce an artefact you
then apply, so the file can change in between and nothing notices. Keep the two
commands adjacent.

Vending is a single deployment here rather than two applies, because Bicep can
pass a runtime subscription ID across a nested deployment boundary. The
workspace still needs `managementSubscriptionId`, so 3.3 is still two runs if
you are vending from scratch.

## 4. Destroy the Terraform tree

Reverse order. Nothing in the deployed set bills more than trivial amounts, so
this is hygiene rather than cost.

```bash
cd terraform/90-optional-network     && terraform destroy
cd ../25-brownfield-seed             && terraform destroy
cd ../20-subscription-placement      && terraform destroy
cd ../10-policy                      && terraform destroy
cd ../00-management-groups           && terraform destroy
```

Take the network down first, and if anything billable is switched on, take that
down before you do anything else at all. Flipping a flag back to false is
cheaper and faster than a full destroy, and it is the thing to reach for if you
just want the meter to stop:

```bash
cd terraform/90-optional-network
terraform apply -var deploy_firewall=false -var deploy_bastion=false   -var deploy_vpn_gateway=false -var deploy_expressroute_gateway=false   -var deploy_route_server=false
```

### `terraform destroy` on 20 will fail, by design

If you vended subscriptions, that third command doesn't
partially succeed. It
fails at plan time:

```
Error: Instance cannot be destroyed
  Resource module.subscription["management"].azurerm_subscription.this has
  lifecycle.prevent_destroy set
```

That guard is deliberate. Destroying `azurerm_subscription` cancels a live
subscription, and a stray `terraform destroy` should not be able to do that.

To get past it, decide what you actually want:

**Keep the subscriptions, drop everything else.** Take them out of state first.
They stay alive in Azure and Terraform stops managing them.

```bash
terraform state rm 'module.subscription["management"]'
terraform state rm 'module.subscription["online-portal-prod"]'
terraform destroy
```

**Actually cancel a subscription.** Do it deliberately and outside this
workflow, from the portal or the `az account subscription cancel` command in
the `account` extension. Cancellation is recoverable for a limited window and
then it isn't. The `Decommissioned` management group exists to hold the result
during that window.

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

There's no `bicep destroy`, and I'm not going to pretend otherwise.
Complete mode is
[resource group scoped only](https://learn.microsoft.com/azure/azure-resource-manager/templates/deployment-modes)
and being deprecated;
[deployment stacks](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks)
are the supported answer but nothing here uses them, and adopting them means
making a `denySettings` decision deliberately rather than picking one up.

So it's manual, in the same reverse order:

```bash
# 5.0 the hub and spoke, including anything billable inside it
az group delete --name rg-hub-network --subscription <connectivity GUID> --yes

# 5.1 the seeded network
az group delete --name rg-legacy-app --subscription <brownfield GUID> --yes

# 5.2 the central workspace
az group delete --name rg-management-logs --subscription <management GUID> --yes

# 5.3 budgets
az consumption budget delete --budget-name budget-demo --subscription <GUID>

# 5.4 policy assignments, and the role assignments their identities hold
az policy assignment delete --name append-costcenter \
  --scope /providers/Microsoft.Management/managementGroups/contoso
# repeat for audit-subnet-nsg, deny-nic-public-ip (twice, two scopes),
# dine-nsg-diagnostics

# 5.5 management groups, deepest first
az account management-group delete --name contoso-lz-corp-audit
# ... then the rest of tier 2, then tier 1, then contoso
```

**`az policy assignment` commands can fail at management group scope** with
`MissingSubscription: The request did not have a subscription or a valid tenant
level resource provider`. It is a CLI quirk, not a permissions problem. Go
straight to the API:

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

**Subscriptions.** They cancel, they don't delete. A cancelled subscription
stays visible for a retention window, which is what `Decommissioned` is for.

**The alias object.** `Microsoft.Subscription/aliases` creates a subscription
and can't update one; Microsoft's documentation is explicit that property
changes made through it aren't retained. Renaming a subscription is a separate
Rename operation.

**The tenant root group.** Not managed by this repository and not deletable.
`contoso` hangs off it, and removing `contoso` leaves the tenant as it was.

## Quick reference

| I want to | Terraform | Bicep |
|---|---|---|
| Preview | `terraform plan -out=tfplan` | `az deployment <scope> what-if` |
| Apply a reviewed preview | `terraform apply tfplan` | not possible, re-runs the template |
| See what exists | `terraform state list` | `az deployment <scope> list` |
| Detect drift | `terraform plan` | `what-if`, when you run it |
| Remove everything | `terraform destroy`, reverse order | by hand, reverse order |
| Stop managing without deleting | `terraform state rm <addr>` | stop deploying the file |
