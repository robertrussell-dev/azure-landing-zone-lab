output "automation_account_id" {
  description = "Resource ID of the Automation account that runs the janitor."
  value       = azurerm_automation_account.janitor.id
}

output "janitor_principal_id" {
  description = "Object ID of the janitor's managed identity. The only principal holding the janitor role."
  value       = azurerm_automation_account.janitor.identity[0].principal_id
}

output "dry_run_command" {
  description = "Starts one run that reports what it would delete and deletes nothing."
  value       = "az automation runbook start --subscription ${var.management_subscription_id} --resource-group ${azurerm_resource_group.automation.name} --automation-account-name ${azurerm_automation_account.janitor.name} --name ${azurerm_automation_runbook.remove_expired.name} --parameters ManagementGroupId=${var.prefix} DryRun=true"
}
