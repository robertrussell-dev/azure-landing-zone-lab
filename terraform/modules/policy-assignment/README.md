# policy-assignment

A policy assignment at management group scope, plus the role assignments its
managed identity needs.

## Why this is a module

Eight callers. The shape is constant and only the data changes: scope,
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
`role_definition_ids` switches identity creation on**:

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
| `parameters` | any | `{}` | Parameters by name. Values can be strings, lists or objects, which is why this isn't `map(any)`: a map needs every value to share one type. The module wraps each value in the `{"value": x}` shape Azure expects. |
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

**Read `role_definition_ids` off the definition.** Every definition declares
what its identity needs:

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

**The `time_sleep` is needed.** Entra takes time to replicate a new managed
identity, and a role assignment against it fails with `PrincipalNotFound` until
it does. Without the wait, applies fail intermittently. Once, the role
assignment took another 32 seconds after the 30 second wait.
