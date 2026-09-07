# One policy assignment at management group scope, plus the role assignments its
# managed identity needs.
#
# This module exists because the repo makes this call five or more times with
# the same shape and different data. A module wrapping a single resource with
# one caller would be indirection for its own sake. See the README.
#
# Effects that need an identity:
#   Modify              needs the roles that let it write the change
#   DeployIfNotExists   needs the roles that let it deploy the remediation
# Effects that do not:
#   Audit, AuditIfNotExists, Deny, Disabled
#
# Passing role_definition_ids is what switches identity creation on.

locals {
  needs_identity = length(var.role_definition_ids) > 0
}

resource "azurerm_management_group_policy_assignment" "this" {
  name                 = var.name
  display_name         = var.display_name
  description          = var.description
  management_group_id  = var.management_group_id
  policy_definition_id = var.policy_definition_id

  # false sets enforcementMode to DoNotEnforce. Compliance is still evaluated
  # and reported, the effect simply does not act. This is what makes an
  # audit only brownfield assignment possible without touching workloads.
  enforce = var.enforce

  # A system assigned identity requires a location. Azure rejects the
  # assignment if an identity is declared without one.
  location = local.needs_identity ? var.location : null

  # Azure expects {"paramName": {"value": x}}. Callers pass a flat map and the
  # module does the wrapping, so call sites stay readable.
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

# The managed identity is created with the assignment, but Microsoft Entra takes
# a moment to replicate it. Creating a role assignment against a principal that
# has not replicated yet fails with PrincipalNotFound. This wait is not
# cosmetic: without it, applies fail intermittently and pass on retry, which is
# the most annoying class of Terraform bug to diagnose.
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
