# A subscription budget with two alert thresholds.
#
# Two thresholds rather than one, and the distinction matters:
#
#   Actual      fires on money already spent. Tells you what happened.
#   Forecasted  fires on projected spend for the period. Tells you what is
#               about to happen, which is the only one that leaves time to act.
#
# A budget notifies. It does not cap spending and it cannot stop a deployment.
# Anything that must not be deployed is prevented by Azure Policy, not by a
# budget. Treating a budget as a control rather than an alarm is how surprise
# bills happen.

resource "azurerm_consumption_budget_subscription" "this" {
  name            = var.name
  subscription_id = "/subscriptions/${var.subscription_id}"

  amount     = var.amount
  time_grain = var.time_grain

  time_period {
    # Budgets must start on the first of a period. Anchoring to the current
    # month keeps the value stable rather than drifting on every apply.
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
    # start_date derives from timestamp(), so without this every plan shows a
    # diff on a value nobody intended to change.
    ignore_changes = [time_period]
  }
}
