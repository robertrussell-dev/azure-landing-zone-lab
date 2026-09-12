# policy-assignment

A policy assignment at management group scope, plus the role assignments its
managed identity needs.

The Bicep counterpart of
[`modules/policy-assignment`](../../../terraform/modules/policy-assignment/). Same five
callers, same interface, one meaningful behavioural difference at the bottom.

## Usage

The management group is the module's scope, not a parameter. That's the one
signature change from the Terraform module, and it's forced: a Bicep module
deploys into a scope, so passing the ID as well would be saying the same thing
twice and allowing the two to disagree.

Audit or Deny effect, no identity needed:

```bicep
module denyPublicIp '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup('${prefix}-lz-corp')
  name: 'assign-deny-nic-public-ip'
  params: {
    name: 'deny-nic-public-ip'
    displayName: 'Network interfaces must not have public IPs'
    policyDescription: 'Corp workloads route egress through the hub.'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', '83a86a26-fd1f-447c-b59d-e51f44264114')
    nonComplianceMessage: 'Route through the hub, or use the Online archetype.'
  }
}
```

Modify or DeployIfNotExists, which need an identity. **Passing
`roleDefinitionIds` is what switches identity creation on**, so an Audit
assignment never grows an identity it has no use for:

```bicep
module appendCostCenter '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup(prefix)
  name: 'assign-append-costcenter'
  params: {
    name: 'append-costcenter'
    displayName: 'Append costCenter tag to resources'
    policyDescription: 'Attribution for spend and cleanup.'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', '4f9dc7db-30c1-420c-b61a-e1d640128d26')
    location: 'westus2'
    roleDefinitionIds: [
      tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    ]
    parameters: {
      tagName: 'costCenter'
      tagValue: 'lab'
    }
  }
}
```

Audit only, for brownfield adoption:

```bicep
module denyPublicIpAudit '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup('${prefix}-lz-corp-audit')
  name: 'assign-deny-nic-public-ip-audit'
  params: {
    // ... same as the enforcing assignment ...
    enforce: false
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | Assignment name. Max 24 characters at management group scope. Immutable. |
| `displayName` | string | required | Shown in the portal compliance view. |
| `policyDescription` | string | required | Why this is assigned here. Written for whoever hits it. Not called `description`, see below. |
| `policyDefinitionId` | string | required | Definition or initiative resource ID. |
| `parameters` | object | `{}` | Flat object. The module wraps each value in the `{value: x}` shape Azure expects. |
| `enforce` | bool | `true` | `false` sets `enforcementMode` to `DoNotEnforce`. |
| `definitionVersion` | string | `''` | Version of a versioned built-in to track, e.g. `1.*.*`. Empty lets Azure default it. See below. |
| `roleDefinitionIds` | array | `[]` | Non-empty creates a system-assigned identity and grants these roles at the assignment scope. |
| `location` | string | `''` | Required when `roleDefinitionIds` is non-empty. |
| `nonComplianceMessage` | string | `''` | Custom message. Azure's default text tells the reader nothing. |

The scope is set by the caller with `scope:`, not passed as an input.

## Outputs

| Name | Description |
|---|---|
| `id` | Resource ID of the assignment. |
| `principalId` | Object ID of the managed identity, or `''` if the effect needs none. |

## Notes

**Read `roleDefinitionIds` off the definition, do not guess them.** Every
definition declares what its identity needs:

```bash
az policy definition show --name <guid> \
  --query "policyRule.then.details.roleDefinitionIds"
```

Two findings from doing exactly that in this repository. The built-in
"Add a tag to resources" Modify policy requires **Contributor**, not Tag
Contributor, so assigning it at an intermediate root grants a policy-created
principal Contributor across the whole hierarchy. And "Subnets should be
associated with a Network Security Group" permits only `AuditIfNotExists` or
`Disabled`, so it cannot be the Deny example it is often presented as. Check
`parameters.effect.allowedValues` before assuming an effect is available.

**`enforce = false` is `DoNotEnforce`, which the portal labels "Disabled".**
One mode, two names. Compliance is still evaluated and recorded; only the
effect stops acting. Note that no Activity log entries are written in this
mode, so an audit period cannot be measured by counting would-have-been-denied
events.

**There is no `time_sleep`, and that is the interesting difference.**

The Terraform module waits 30 seconds between creating the assignment and
creating the role assignments for its identity. Microsoft Entra takes time to
replicate a newly created managed identity, and creating a role assignment
against a principal that hasn't replicated fails with `PrincipalNotFound`.
Without the wait, applies fail intermittently and pass on retry. Observed
there: the role assignment took a further 32 seconds to succeed after a 30
second wait.

ARM handles this itself, if you tell it what kind of principal it is. Setting
`principalType: 'ServicePrincipal'` on the role assignment is the documented
fix for exactly this error, and it needs `apiVersion` `2018-09-01-preview` or
later - `2022-04-01` is the first stable version that carries it, and it's what
this module pins. Microsoft's own troubleshooting page names the error and
prescribes the property:
[Troubleshoot Azure RBAC](https://learn.microsoft.com/azure/role-based-access-control/troubleshooting#azure-role-assignments).

Worth being precise about what the difference actually is, because it's easy to
tell as a Bicep-is-better story and that isn't it. The Terraform module sets
`principal_type = "ServicePrincipal"` as well. It carries the wait *in addition*
to the property, and I haven't gone back to test whether removing the wait now
passes reliably - the sleep went in because applies were failing, and I've left
it. So the honest statement is that this module doesn't need a wait and the
Terraform one has one, not that the property is missing over there.

**`definitionVersion` exists because what-if found it.** Built-in definitions
are versioned, and an assignment records which versions it tracks. Nothing in
the Terraform configuration sets one - the azurerm provider has no such
attribute in state - and yet the assignments it created carry `1.*.*` and
`3.*.*`, so Azure applied them itself at creation.

A what-if of this module against those assignments reports
`- properties.definitionVersion`, because what-if diffs the literal template
payload against current state and doesn't model server-side defaults. Whether
a real deployment would strip the value or Azure would re-apply the same
default is untested, and testing it means deploying on top of the Terraform
tree, which
[isn't possible](../../README.md#what-if-against-the-deployed-estate) for an
unrelated reason.

So the parameter is here to make the property expressible, and it's left empty.
Setting a version on a definition that isn't versioned is an error, and the
right value differs per definition, so guessing one to silence a what-if line
would be the wrong trade.

**Parameter named `policyDescription`.** A parameter called `description`
shadows the `@description` decorator for the whole file. Every decorator below
it then fails with `BCP062: The referenced declaration with name "description"
is not valid`, which names the decorator and not the cause.
