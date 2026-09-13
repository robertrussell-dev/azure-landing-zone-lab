# policy-assignment

A policy assignment at management group scope, plus the role assignments its
managed identity needs.

The Bicep counterpart of
[`modules/policy-assignment`](../../../terraform/modules/policy-assignment/), with the
same interface and one behavioral difference, described at the bottom.

## Usage

The management group is the module's scope, not a parameter. That's the one
signature change from the Terraform module: passing the ID as well would let
the two disagree.

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
`roleDefinitionIds` switches identity creation on**:

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

**Read `roleDefinitionIds` off the definition.** Every definition declares what
its identity needs:

```bash
az policy definition show --name <guid> \
  --query "policyRule.then.details.roleDefinitionIds"
```

The built in "Add a tag to resources" Modify policy requires **Contributor**,
not Tag Contributor. "Subnets should be associated with a Network Security
Group" only allows `AuditIfNotExists` or `Disabled`. Check
`parameters.effect.allowedValues` before assuming an effect is available.

**`enforce = false` is `DoNotEnforce`, which the portal calls "Disabled".**
Compliance is still evaluated; only the effect stops acting. No Activity log
entries are written in this mode.

**There's no `time_sleep`.** The Terraform module waits 30 seconds before
granting roles to the new identity, because Entra replication lags and the role
assignment fails with `PrincipalNotFound`. (Once, it took another 32 seconds
after the wait.) Setting `principalType: 'ServicePrincipal'` makes ARM retry
instead, which Microsoft's
[troubleshooting page](https://learn.microsoft.com/azure/role-based-access-control/troubleshooting#azure-role-assignments)
documents for this error. It needs API version `2018-09-01-preview` or later,
and this module pins `2022-04-01`.

That isn't Bicep being better. The Terraform module sets `principal_type` too
and keeps the wait as well; whether it still needs the wait is untested.

**`definitionVersion` exists because what-if found it.** Built in definitions
are versioned, and the assignments Terraform created carry `1.*.*` and `3.*.*`
even though azurerm never set them, so Azure applied defaults. what-if reports
`- properties.definitionVersion` because it doesn't model server-side
defaults. Whether a real deployment would strip the value is untested, since it
would mean deploying over the Terraform tree, which
[can't be done](../../README.md#what-if-against-the-deployed-estate). The
parameter is left empty: setting a version on an unversioned definition is an
error, and the right value differs per definition.

**`policyDescription`, not `description`.** A parameter called `description`
shadows the `@description` decorator, and every decorator below it fails with
`BCP062: The referenced declaration with name "description" is not valid`.
