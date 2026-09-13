output "subscription_id" {
  description = "Bare GUID of the created subscription."
  value       = azurerm_subscription.this.subscription_id
}

output "subscription_resource_id" {
  description = "Full resource ID, for use as a scope in policy or role assignments."
  value       = "/subscriptions/${azurerm_subscription.this.subscription_id}"
}

output "management_group_id" {
  description = "Management group the subscription was placed under."
  value       = var.management_group_id
}

output "budget_id" {
  description = "Resource ID of the subscription budget."
  value       = module.budget.id
}

output "remaining_steps" {
  description = "Steps vending leaves to the caller. See the module README."
  value = [
    "Register any resource providers the workload needs beyond the platform baseline. A new subscription has almost none, and the failure is a 409 naming the namespace rather than the cause.",
    "Configure an azurerm provider for this subscription ID and deploy workload resources in a second apply.",
    "Assign workload team access at subscription or resource group scope, never at management group scope.",
  ]
}
