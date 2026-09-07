output "id" {
  description = "Resource ID of the policy assignment."
  value       = azurerm_management_group_policy_assignment.this.id
}

output "principal_id" {
  description = "Object ID of the assignment's managed identity, or null if the effect does not need one."
  value       = local.needs_identity ? azurerm_management_group_policy_assignment.this.identity[0].principal_id : null
}
