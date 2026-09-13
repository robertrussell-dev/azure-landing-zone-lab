# The same landing zone, in Bicep

Everything in [`terraform/`](../terraform/), written again in Bicep: the same
hierarchy, the same eight policy assignments, the same brownfield pattern. The
ADRs in [`docs/adr`](../docs/adr/) describe both trees, because none of them
turned on the tool.

I wrote it to find out which parts of the Terraform were architecture and which
were just Terraform. Some turned out to be neither, and those are under
[What's actually different](#whats-actually-different).

## Layout

Directories are numbered in deployment order and match `terraform/` one for one.

| Directory | Scope | What it does |
|---|---|---|
| [`00-management-groups`](00-management-groups/) | management group | The 13 group hierarchy, plus the hierarchy settings and a custom role on the tenant root group. The groups are tenant resources; only the deployment runs lower. |
| [`10-policy`](10-policy/) | management group | The eight policy assignments, two of them the subscription baseline. |
| [`20-subscription-placement`](20-subscription-placement/) | tenant | Brownfield placement, budgets, vending, the subscription baseline, the central workspace and its lock. |
| [`25-brownfield-seed`](25-brownfield-seed/) | subscription | Resources that break the policy set on purpose, so the audit only assignment has something to report. |
| [`30-auto-delete`](30-auto-delete/) | two stacks | The janitor that deletes billable devices past their `deleteAfter` time. The only root deployed as stacks, and the only one with a real destroy. |
| [`90-optional-network`](90-optional-network/) | subscription | Hub and spoke, from docs/ip-plan.md. Free layer by default, billable devices behind flags. |
| [`modules`](modules/) | n/a | The five reusable child modules. |

Every root resolves management group scopes by name, so there's no state to
share and no ordering beyond the directory numbers.

![Bicep deployment scopes](../docs/diagrams/bicep-deployment-scopes.svg)

## Deploying

[runbooks/deploy-and-destroy.md](../runbooks/deploy-and-destroy.md) walks both
trees end to end. This section only covers the Bicep commands.

Each root takes a `.bicepparam` file. Copy the committed example. CI compiles
the examples against their templates, so a renamed parameter breaks the build
instead of the deployment.

```bash
cd bicep/00-management-groups
cp main.example.bicepparam main.bicepparam   # fill in prefix and display name

# The tenant root management group's ID is the tenant ID.
MG=$(az account show --query tenantId -o tsv)

az deployment mg what-if \
  --management-group-id "$MG" \
  --location westus2 \
  --template-file main.bicep \
  --parameters main.bicepparam

az deployment mg create \
  --management-group-id "$MG" \
  --location westus2 \
  --template-file main.bicep \
  --parameters main.bicepparam
```

That's a management group deployment creating tenant level resources, for the
reason in [Scope replaces the provider](#scope-replaces-the-provider). It runs
at the tenant root group because the hierarchy settings and the custom role
belong there.

Then the rest, each at its own scope:

```bash
az deployment mg create --management-group-id contoso --location westus2 \
  --template-file bicep/10-policy/main.bicep --parameters bicep/10-policy/main.bicepparam

az deployment tenant create --location westus2 \
  --template-file bicep/20-subscription-placement/main.bicep \
  --parameters bicep/20-subscription-placement/main.bicepparam

az deployment sub create --subscription <brownfield GUID> --location westus2 \
  --template-file bicep/25-brownfield-seed/main.bicep \
  --parameters bicep/25-brownfield-seed/main.bicepparam
```

`30-auto-delete` is two `az stack mg create` commands, listed in its
[`main.bicep`](30-auto-delete/main.bicep) header.

**Run what-if first.** It's the nearest thing to `terraform plan -out`, but it
predicts and doesn't produce anything you then apply. The file can change
between the what-if and the create. Keep the two commands adjacent. At tenant
and management group scope, what-if needs the same access as the deployment.

**`az deployment` compiles with the Azure CLI's bundled Bicep, not the pinned
one.** Resource type schemas ship inside the compiler, so an old bundled copy
stops validating newer types and only warns:

```
Warning BCP081: Resource type "Microsoft.Network/virtualNetworks@2025-09-01"
does not have types available. Bicep is unable to validate resource properties
prior to deployment, but this will not block the resource from being deployed.
```

That came from Bicep 0.39.26. Either bring the CLI's copy up to the version in
[`scripts/install-bicep.sh`](../scripts/install-bicep.sh) with
`az bicep install --version v0.47.16`, or build with the pinned binary and
deploy the JSON.

**Check the tenant before the first deployment.** `00-management-groups`
outputs `deployedToTenantId` for this; see
[No tenant pin](#no-tenant-pin-in-configuration).

## Destroying

There's no `bicep destroy`.

- Complete mode deletes whatever a template doesn't declare, but it's
  [resource group scoped only](https://learn.microsoft.com/azure/azure-resource-manager/templates/deployment-modes)
  and being deprecated.
- [Deployment stacks](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks)
  work at resource group, subscription and management group scope, not tenant,
  which rules out `20`. Their `denySettings` change who can touch the managed
  resources, so adopting them is a decision.
  [ADR 0008](../docs/adr/0008-delete-protection.md) makes it for
  `30-auto-delete` only.
- Everything else comes down by hand: `az group delete`,
  `az policy assignment delete`, `az account management-group delete`, in the
  same order as the Terraform destroy.

Nothing deployed bills more than trivial amounts, so teardown is hygiene. The
exception is a vended subscription, and canceling one happens outside this
workflow in both trees.

## What's actually different

None of this is an architecture decision, which is why it isn't in the ADRs.

### Scope replaces the provider

An azurerm provider is a connection. Pin a tenant and subscription to it and it
reaches anything you have rights to, management groups included. A Bicep
deployment has a scope instead, every `resource` in a file belongs to it, and a
module is how you cross into another.

`20-subscription-placement` has to be a **tenant** deployment, because
`Microsoft.Subscription/aliases` is a tenant only type. That needs Owner or
Contributor at `/`.

`00-management-groups` doesn't, even though management groups are tenant
resources too. A resource can carry `scope: tenant()` from a deployment running
lower down, so it's a **management group** deployment that creates tenant level
groups. The groups end up in the same place; only the deployment record moves.

That matters for permissions. Root scope `/` only accepts built in roles, so the
narrowest grant there is Contributor over the whole tenant. A management group
takes custom roles, so the same work can be authorized with
`Microsoft.Resources/deployments/*` and `Microsoft.Management/managementGroups/*`
and nothing else. [The permission wall](#the-permission-wall) is how I found
this out.

It also means a file can be a module for reasons unrelated to reuse.
`20-subscription-placement/management-logs.bicep` exists because a resource
group is a subscription level resource and the workspace inside it isn't. The
two caller rule in [modules/README.md](modules/README.md) decides what goes in
`modules/`, not what gets split.

### No tenant pin in configuration

`terraform/00-management-groups/providers.tf` pins `tenant_id` and
`subscription_id`, so a stray `az account set` can't send an apply to the wrong
tenant. A Bicep file can't do that. Scope comes from the CLI's signed in
context. The nearest guard is the `deployedToTenantId` output, which shows up in
what-if. You have to read it; it won't stop you. That's a plain loss.

### No state

The Terraform README lists local state as a constraint for a team. That
constraint doesn't exist here, and neither do these:

- **Drift detection.** what-if compares the template with reality when you ask.
  Nothing tells you otherwise.
- **Destroy**, covered above.
- **`moved` blocks.** ARM identifies a resource by type, name and scope, so
  extracting a module can't cause a destroy and recreate. The flip side is that
  a refactor leaves nothing in the code for a reviewer to check.
- **`ignore_changes`**, which is the one that hurts. See the next section.

### The Modify policy fight is silent instead of loud

In `terraform/25-brownfield-seed` the Modify assignment appends `costCenter`,
Terraform finds a tag it didn't declare, and plans to remove it on every run
until `ignore_changes` settles who owns the field.

Here an incremental deployment
[resets properties the template doesn't declare](https://learn.microsoft.com/azure/azure-resource-manager/templates/deployment-modes),
so a redeploy strips `costCenter` and the policy puts it back at the next
evaluation. what-if does show it, as `- tags.costCenter: "lab"`, but only if
someone runs it. Terraform shows it on every plan. I'd take the visible version.

### Three things Bicep does that Terraform can't

**Vending is one deployment.** azurerm can't create anything inside the
subscription it creates, because a provider needs `subscription_id` at plan
time, so the Terraform baseline uses azapi. Bicep hits a similar wall, since a
module scope has to resolve before the deployment starts, but gets past it by
passing the ID one level down as a parameter. Placement and the budget happen
in the same run. Details and the compiler error are in
[`modules/subscription-vending`](modules/subscription-vending/).

![Subscription vending nesting](../docs/diagrams/vending-nesting.svg)

**No wait before the role assignment.** The Terraform `policy-assignment` module
sleeps 30 seconds so the policy's managed identity can replicate before it gets
roles. This one doesn't need to; why is in
[`modules/policy-assignment`](modules/policy-assignment/).

**Resource providers register themselves.** A Bicep deployment registers the
provider for every type it declares. Terraform doesn't, so the Terraform network
registers `Microsoft.Network` and `subscription-baseline` registers three more.
The gap here is `Microsoft.PolicyInsights`, which no template declares and a
subscription needs before it reports compliance. It's registered outside this
tree.

### The janitor

`30-auto-delete` is the same design in both trees and comes out different in
three ways.

**The runbook is a URL.** azurerm uploads the script as content. An ARM runbook
only has `publishContentLink`, which Automation downloads from, so the parameter
file pins it to a commit. A branch URL would publish unreviewed changes.

**The clock restarts on every deployment.** Terraform writes `deleteAfter` once,
from `plantimestamp()`, and `ignore_changes` keeps it. Bicep has no way to
remember the first value, so the tag comes from `utcNow()` and every deployment
of `90` restamps every device that's on. That extends a device's life whether or
not you meant to.

**Only this side is protected from deletion.** A stack with `denyDelete` owns
the Automation account. Terraform has no equivalent short of deploying a stack
through azapi, which [ADR 0008](../docs/adr/0008-delete-protection.md) rejects,
along with the two stack rules that split this root in two.

### Small things that cost time

- A parameter named `description` shadows the `@description` decorator and
  breaks every decorator after it. It's `policyDescription` here.
- No float literals. `dailyQuotaGb: 0.1` is a parse error; use `json('0.1')`.
- Loops are positional, not keyed. It doesn't matter, because ARM addresses
  resources by name.
- Deployment names are capped at 64 characters, and the compiler warns when an
  interpolated name *might* exceed it. Hence the `take(...)` calls.
- `subnets` go inline on the virtual network. Mixing inline and child subnets
  makes alternate deployments overwrite each other.
- A DNS resolver subnet delegation gains a `subnets/join/action` once deployed.
  Terraform has to declare it or plans to remove it. Bicep's type marks it read
  only, so declaring it fails lint, and what-if ignores it.
- A lock on a resource group can't be declared from the subscription scoped file
  that creates the group: it fails with `BCP139`. The lock lives in the
  workspace's resource group scoped file with no `scope`.

## Validation

The checks live in [`scripts/`](../scripts/) and both CI definitions call them.
No Azure credentials anywhere.

| Script | What it does |
|---|---|
| `install-bicep.sh` | Installs a pinned Bicep CLI directly, not through `az bicep`. |
| `validate-bicep.sh` | Format check, `bicep build` on every file, `bicep build-params` on every committed example. |
| `lint-bicep.sh` | `bicep lint`, failing on any output, because it exits 0 on warnings. |
| `scan-security.sh` | checkov, both trees. |

`bicep build` works offline with the schemas bundled in the CLI, so the pinned
version decides what the build checks against. Linter settings, with reasons for
the two rules turned off, are in [`bicepconfig.json`](bicepconfig.json).

**checkov scans this tree as compiled ARM JSON.** Its Bicep parser can't read
lambda expressions, which `modules/policy-assignment` uses, and it exits 0 on a
parse error. Scanning the compiled JSON avoids the parser and covers 46
resources instead of 24. `scan-security.sh` also fails on any parse error, since
an unreadable file otherwise looks clean.

## What-if against the deployed estate

The Terraform tree is deployed with `prefix = "contoso"`. Pointed at the same
prefix, what-if compares the Bicep with what Terraform built. That's as close as
this gets to proving the translation without deploying it. All six roots have
been run: five against what Terraform deployed, and `30-auto-delete` against the
estate it would deploy into.

| Root | Result |
|---|---|
| `00-management-groups` | 15 resources, all `Nochange`: every group, the hierarchy settings and the custom role. |
| `10-policy` | The seven assignments deployed at the time matched on name, scope, definition, parameters, enforcement, display name, description and message. The eighth, from ADR 0008, was a create in both trees. |
| `20-subscription-placement` | The Corp (audit only) group, workspace, resource group, Defender plan and security contact match. The budget doesn't. |
| `25-brownfield-seed` | Resource group unchanged; three expected property diffs on the network. |
| `30-auto-delete` | Seven creates, matching Terraform's eight minus its replication wait. |
| `90-optional-network` | Resource group and all seven exemptions unchanged; every network diff explained below. |

Four things were worth fixing, listed at the end of this section. The rest of
the diffs fall into a few groups.

**Server-side defaults.** `definitionVersion` on policy assignments,
`privateEndpointVNetPolicies` on virtual networks, a budget's `endDate`, and the
state fields on peerings are values Azure fills in. what-if can't model them.

**The Modify tag.** `- tags.costCenter` on every network resource, as described
[above](#the-modify-policy-fight-is-silent-instead-of-loud).

**Role assignment names.** `10-policy` reports six role assignments as creates.
The grants exist; Terraform named them with different GUIDs than
`guid(managementGroup().id, name, roleDefinitionId)` produces. A deployment
would fail with `RoleAssignmentExists`, so the two trees can't both manage this
tenant, and not just because the group names clash.

**Budget notification keys.** Terraform's provider generated
`actual_GreaterThan_80.000000_Percent`, and this module uses `actual`. A
deployment would delete one and create the other. The generated key embeds the
threshold, so it changes whenever the threshold does. what-if also can't
evaluate the budget's `utcNow()` start date and prints the raw expression,
which is why [the module README](modules/subscription-budget/) says to pin
`startDate` once a budget exists.

The four fixes:

- The intermediate root omitted `details.parent`, relying on the tenant root
  default, as the Terraform does. Against an existing group, what-if read the
  omission as removing the parent. It now names the tenant root explicitly.
- The seeded subnet declared `addressPrefix` where the API returns
  `addressPrefixes`, so every what-if showed a false change.
- `defaultOutboundAccess` was set by neither tree. The deployed subnet has
  `true` from the provider's API version, and `2025-09-01` defaults it to
  `false`, so an API version bump would have changed egress on an untouched
  subnet. It's explicit now.
- `policy-assignment` gained a `definitionVersion` parameter, left empty, so a
  version can be pinned when one matters. Details in
  [its README](modules/policy-assignment/#notes).

`10`, `20` and `90` were run again on 12 September, after ADR 0008. Every new
resource showed as a create and matched the Terraform plan: one assignment in
`10`, the lock and two tag changes in `20`, nothing new in `90`. There's no
what-if for stacks, so `30` was also put through `az stack mg validate`, which
is where both of ADR 0008's stack rules came from.

### The permission wall

The first what-if on `00` and `20` failed, because both were tenant deployments
then:

```
(AuthorizationFailed) The client '...' does not have authorization to perform
action 'Microsoft.Resources/deployments/whatIf/action' over scope
'/providers/Microsoft.Resources/deployments/main'
```

The account held User Access Administrator at `/`, from Entra elevated access,
and Owner on the intermediate root. That was enough to build the hierarchy
through Terraform and not enough for a tenant deployment, because
`Microsoft.Authorization/*` doesn't include `Microsoft.Resources/deployments/*`.
A narrow custom role can't fix it at `/`: custom roles
[can't be assigned there](https://learn.microsoft.com/azure/role-based-access-control/custom-roles#custom-role-limits),
and the narrowest built in role with that action is tenant-wide Contributor.

`00-management-groups` became a management group deployment with
`scope: tenant()` on its groups, the pattern Microsoft
[documents](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-management-group#management-group)
for this. The what-if result didn't change. The narrow role that's illegal at
`/` is fine at a management group, and it now exists in both trees as
`contoso hierarchy deployer`. It's defined, not demonstrated: the account here
holds Owner at `/`, which would hide whether the narrower role is enough.

`20-subscription-placement` has no equivalent route and still needs it.

**The lab operator holds Owner at `/` and elevated access, permanently.** In a
real estate neither would be acceptable: Microsoft's guidance is that elevated
access is temporary. This is a single user tenant where the alternative is
re-elevating for every preview, and I'd rather it be written down than found.
The restructure fixed one root out of two.

## What isn't here

**[ALZ-Bicep](https://github.com/Azure/ALZ-Bicep)**, for the same reason as
`Azure/avm-ptn-alz/azurerm` on the Terraform side. ADR 0007 covers both.

**A deployment.** This tree has never been applied. What's running in the tenant,
and the evidence in [`docs/evidence`](../docs/evidence/), is the Terraform.
what-if is a weaker claim than a deployment and a much stronger one than a
compile.
