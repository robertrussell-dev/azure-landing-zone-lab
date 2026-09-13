# Subscription vending: create a subscription, place it, budget it.
#
# Resources inside the new subscription can't be created in the same apply,
# because a provider needs the subscription ID at plan time. The README covers
# what that means and how the baseline gets around it.

resource "azurerm_subscription" "this" {
  subscription_name = var.display_name

  # The alias names the alias object and is immutable. Reusing an existing one
  # adopts that subscription instead of creating a new one.
  alias            = var.alias == null ? var.display_name : var.alias
  billing_scope_id = var.billing_scope_id
  workload         = var.workload

  tags = var.tags

  lifecycle {
    # Destroying this cancels the subscription. That's done by hand, outside
    # Terraform. See ADR 0008.
    prevent_destroy = true
  }
}

# New subscriptions land at the tenant root, so placement is a second step. It
# has to happen before anything is deployed inside; the onboarding runbook says
# why.
resource "azurerm_management_group_subscription_association" "this" {
  management_group_id = var.management_group_id
  subscription_id     = "/subscriptions/${azurerm_subscription.this.subscription_id}"
}

module "budget" {
  source = "../subscription-budget"

  name            = "budget-${var.display_name}"
  subscription_id = azurerm_subscription.this.subscription_id
  amount          = var.budget_amount
  contact_emails  = var.budget_contact_emails

  actual_threshold_percent   = var.budget_actual_threshold_percent
  forecast_threshold_percent = var.budget_forecast_threshold_percent

  depends_on = [azurerm_management_group_subscription_association.this]
}

# Resource providers and Defender's free tier. The same people who get the
# budget alerts get the security alerts.
module "baseline" {
  source = "../subscription-baseline"

  subscription_id         = azurerm_subscription.this.subscription_id
  security_contact_emails = var.budget_contact_emails

  # Waits for placement, like the budget.
  depends_on = [azurerm_management_group_subscription_association.this]
}
