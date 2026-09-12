# The subscription baseline for the adopted brownfield subscription. Vended
# subscriptions get theirs from modules/subscription-vending.
module "baseline_brownfield" {
  source = "../modules/subscription-baseline"

  subscription_id         = var.brownfield_subscription_id
  security_contact_emails = var.budget_alert_emails
}
