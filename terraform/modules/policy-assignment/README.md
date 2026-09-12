# policy-assignment

A policy assignment at management group scope, plus the role assignments its
managed identity needs.

## Why this is a module

Five callers. The shape is constant and only the data changes: scope,
definition, parameters, enforcement mode.

## Usage

Audit or Deny effect, no identity needed:

```hcl
module "deny_public_ip" {
  source = "../../modules/policy-assignment"

  name                 = "deny-nic-public-ip"
  display_name         = "Network interfaces must not have public IPs"
  description          = "Corp workloads route egress through the hub."
  management_group_id  = data.azurerm_management_group.corp.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114"

  non_compliance_message = "Route through the hub, or use the Online archetype."
}
```

Modify or DeployIfNotExists, which need an identity. **Passing
`role_definition_ids` is what switches identity creation on**, so an Audit
assignment never grows an identity it has no use for:

```hcl
module "append_cost_center" {
  source = "../../modules/policy-assignment"

  name                 = "append-costcenter"
  display_name         = "Append costCenter tag to resources"
  description          = "Attribution for spend and cleanup."
  management_group_id  = data.azurerm_management_group.root.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/4f9dc7db-30c1-420c-b61a-e1d640128d26"

  location            = "westus2"
  role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]

  parameters = {
    tagName  = "costCenter"
    tagValue = "lab"
  }
}
```

Audit only, for brownfield adoption:

```hcl
module "deny_public_ip_audit" {
  source = "../../modules/policy-assignment"
  # ... same as the enforcing assignment ...
  enforce = false
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | Assignment name. Max 24 characters at management group scope. Immutable. |
| `display_name` | string | required | Shown in the portal compliance view. |
| `description` | string | required | Why this is assigned here. Written for whoever hits it. |
| `management_group_id` | string | required | Full resource ID of the scope. |
| `policy_definition_id` | string | required | Definition or initiative resource ID. |
| `parameters` | map(any) | `{}` | Flat map. The module wraps each value in the `{"value": x}` shape Azure expects. |
| `enforce` | bool | `true` | `false` sets `enforcementMode` to `DoNotEnforce`. |
| `role_definition_ids` | list(string) | `[]` | Non-empty creates a system-assigned identity and grants these roles at the assignment scope. |
| `location` | string | `null` | Required when `role_definition_ids` is non-empty. |
| `non_compliance_message` | string | `null` | Custom message. Azure's default text tells the reader nothing. |

## Outputs

| Name | Description |
|---|---|
| `id` | Resource ID of the assignment. |
| `principal_id` | Object ID of the managed identity, or `null` if the effect needs none. |

## Notes

**Read `role_definition_ids` off the definition, do not guess them.** Every
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

**The `time_sleep` is not padding.** Microsoft Entra takes time to replicate a
newly created managed identity, and creating a role assignment against a
principal that has not replicated fails with `PrincipalNotFound`. Without the
wait, applies fail intermittently and pass on retry, which is the most annoying
class of Terraform bug to diagnose. Observed here: the role assignment took a
further 32 seconds to succeed after a 30 second wait.
