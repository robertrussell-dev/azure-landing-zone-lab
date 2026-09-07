# Subscription vending.
#
# This is real, not a described process. The alias API creates the
# subscription against a billing scope, and the platform team places it. Both
# steps are here because both are the platform team's job.
#
# Billing scope permissions are a separate model from Azure RBAC. Owner on a
# management group grants nothing here. The caller needs Owner, Contributor or
# Azure subscription creator on the invoice section, billing profile or billing
# account. That split is the most common blocker when a team first automates
# this, and it is why the runbook calls it out.

module "management_subscription" {
  source = "../../modules/subscription-vending"
  count  = var.create_management_subscription ? 1 : 0

  display_name     = var.management_subscription_name
  billing_scope_id = var.billing_scope_id

  management_group_id = data.azurerm_management_group.platform_management.id

  budget_amount         = var.monthly_budget_amount
  budget_contact_emails = var.budget_alert_emails

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }
}

moved {
  from = azurerm_subscription.management[0]
  to   = module.management_subscription[0].azurerm_subscription.this
}

moved {
  from = azurerm_management_group_subscription_association.management[0]
  to   = module.management_subscription[0].azurerm_management_group_subscription_association.this
}

moved {
  from = module.budget_management[0].azurerm_consumption_budget_subscription.this
  to   = module.management_subscription[0].module.budget.azurerm_consumption_budget_subscription.this
}
