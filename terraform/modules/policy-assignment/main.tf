# One policy assignment at management group scope, plus the role assignments its
# managed identity needs.
#
#
# Effects that need an identity:
#   Modify              needs the roles that let it write the change
#   DeployIfNotExists   needs the roles that let it deploy the remediation
# Effects that do not:
#   Audit, AuditIfNotExists, Deny, DenyAction, Disabled
#
# Passing role_definition_ids switches identity creation on.

locals {
  needs_identity = length(var.role_definition_ids) > 0
}

resource "azurerm_management_group_policy_assignment" "this" {
  name                 = var.name
  display_name         = var.display_name
  description          = var.description
  management_group_id  = var.management_group_id
  policy_definition_id = var.policy_definition_id

  # false is DoNotEnforce: still evaluated and reported, but the effect doesn't
  # act.
  enforce = var.enforce

  # A system assigned identity requires a location. Azure rejects the
  # assignment if an identity is declared without one.
  location = local.needs_identity ? var.location : null

  # Azure expects {"paramName": {"value": x}}; callers pass a flat map.
  parameters = length(var.parameters) > 0 ? jsonencode({
    for k, v in var.parameters : k => { value = v }
  }) : null

  dynamic "identity" {
    for_each = local.needs_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_message == null ? [] : [1]
    content {
      content = var.non_compliance_message
    }
  }
}

# Entra takes a moment to replicate the new identity. Without this wait the role
# assignment intermittently fails with PrincipalNotFound.
resource "time_sleep" "identity_propagation" {
  count = local.needs_identity ? 1 : 0

  depends_on      = [azurerm_management_group_policy_assignment.this]
  create_duration = "30s"
}

resource "azurerm_role_assignment" "identity" {
  for_each = local.needs_identity ? toset(var.role_definition_ids) : toset([])

  scope              = var.management_group_id
  role_definition_id = each.value
  principal_id       = azurerm_management_group_policy_assignment.this.identity[0].principal_id
  principal_type     = "ServicePrincipal"

  depends_on = [time_sleep.identity_propagation]
}
