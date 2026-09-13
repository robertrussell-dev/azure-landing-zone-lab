# A subscription budget with two alerts: actual spend, and forecast spend, which
# fires early enough to act on. A budget only notifies; it caps nothing.

resource "azurerm_consumption_budget_subscription" "this" {
  name            = var.name
  subscription_id = "/subscriptions/${var.subscription_id}"

  amount     = var.amount
  time_grain = var.time_grain

  time_period {
    # Budgets start on the first of a period.
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = var.actual_threshold_percent
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.contact_emails
  }

  notification {
    enabled        = true
    threshold      = var.forecast_threshold_percent
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.contact_emails
  }

  lifecycle {
    # start_date comes from timestamp(), which changes on every plan.
    ignore_changes = [time_period]
  }
}
