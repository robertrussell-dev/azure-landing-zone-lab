# Budget on the brownfield subscription. Vended subscriptions get theirs from
# modules/subscription-vending.
#
# The moved block kept the budget from being destroyed and recreated when it
# moved into the module.

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

