# Budgets for every subscription in the estate.
#
# These were two near identical inline resource blocks before, one per
# subscription. That duplication is what earned the module: the shape is
# constant and only the data changes, and every subscription this platform
# vends will need one.
#
# The moved blocks below migrate the existing budgets into the module in
# Terraform state. Without them, refactoring into a module changes each
# resource's address, and Terraform reads an address change as "destroy the old
# one, create a new one". For a budget that is merely noisy. For a resource
# that carries data it would be destructive, which is why moved blocks are the
# right tool rather than terraform state mv run by hand and undocumented.

module "budget_brownfield" {
  source = "../modules/subscription-budget"

  name            = "budget-${var.brownfield_subscription_name}"
  subscription_id = var.brownfield_subscription_id
  amount          = var.monthly_budget_amount
  contact_emails  = var.budget_alert_emails
}


moved {
  from = azurerm_consumption_budget_subscription.brownfield
  to   = module.budget_brownfield.azurerm_consumption_budget_subscription.this
}

