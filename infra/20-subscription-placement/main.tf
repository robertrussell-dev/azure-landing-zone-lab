# Subscription placement and cost guardrails.
#
# Placement is deliberately separate from creation. Subscriptions created
# through the alias API land in the tenant root management group and are moved
# afterwards, so "create" and "place" are always two operations. Modelling them
# separately matches what actually happens rather than hiding it.
#
# Management group scopes are looked up by name for the same reason as
# infra/10-policy: the names are derived from the prefix, so nothing needs to
# be passed between root modules and each directory applies independently.

data "azurerm_management_group" "corp_audit" {
  name = "${var.prefix}-lz-corp-audit"
}

data "azurerm_management_group" "platform_management" {
  name = "${var.prefix}-platform-management"
}

# ---------------------------------------------------------------------------
# Brownfield placement
# ---------------------------------------------------------------------------
# DemoSubscription predates this landing zone. It is the brownfield case, and
# it is placed under the audit only Corp archetype rather than Corp itself.
#
# What this demonstrates, and the reason it is worth doing rather than
# describing: the subscription is now evaluated against the Corp policy set,
# including the Deny on public IPs, and none of it is enforced. Compliance is
# measured with zero risk to whatever is running. Moving this association to
# the real Corp management group is the single change that turns enforcement
# on, with no policy rewritten. See ADR 0005.
resource "azurerm_management_group_subscription_association" "brownfield" {
  management_group_id = data.azurerm_management_group.corp_audit.id
  subscription_id     = "/subscriptions/${var.brownfield_subscription_id}"
}

# ---------------------------------------------------------------------------
# Cost guardrails
# ---------------------------------------------------------------------------
# Every subscription in this lab carries a budget with alerts. Cost is treated
# as a correctness requirement, not a reporting afterthought, because this runs
# on a personal card.
#
# Two thresholds on purpose:
#   Actual 80    tells you what has already been spent
#   Forecasted 100  tells you where the month is heading, which is the one that
#                   gives you time to act
#
# A budget does not stop spending. It notifies. Anything that must not be
# deployed is prevented by policy, not by a budget.
resource "azurerm_consumption_budget_subscription" "brownfield" {
  name            = "budget-${var.brownfield_subscription_name}"
  subscription_id = "/subscriptions/${var.brownfield_subscription_id}"

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
    # Budgets must start on the first of a month. Anchoring to the current
    # month keeps this from drifting every time it is reapplied.
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget_alert_emails
  }

  lifecycle {
    # start_date is computed from timestamp(), so it would show a diff on every
    # plan. The budget's start month is not something to churn.
    ignore_changes = [time_period]
  }
}
