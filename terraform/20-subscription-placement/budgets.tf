# Budget on the brownfield subscription. Vended subscriptions get theirs from
# modules/subscription-vending.

module "budget_brownfield" {
  source = "../modules/subscription-budget"

  name            = "budget-${var.brownfield_subscription_name}"
  subscription_id = var.brownfield_subscription_id
  amount          = var.monthly_budget_amount
  contact_emails  = var.budget_alert_emails
}

