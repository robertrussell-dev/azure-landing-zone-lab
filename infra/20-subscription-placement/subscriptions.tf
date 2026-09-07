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

resource "azurerm_subscription" "management" {
  count = var.create_management_subscription ? 1 : 0

  subscription_name = var.management_subscription_name

  # The alias name is the resource ID of the alias object, not the
  # subscription. It is immutable and must be unique in the tenant.
  alias            = var.management_subscription_name
  billing_scope_id = var.billing_scope_id

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }

  lifecycle {
    # Destroying this resource cancels the subscription. Cancellation is
    # recoverable for a limited window, but a "terraform destroy" that quietly
    # cancels a platform subscription is not a failure mode worth leaving open.
    # Removing a subscription is a deliberate act done outside this workflow.
    prevent_destroy = true
  }
}

# Subscriptions created through the alias API land in the tenant root
# management group. Placement is always a second operation.
resource "azurerm_management_group_subscription_association" "management" {
  count = var.create_management_subscription ? 1 : 0

  management_group_id = data.azurerm_management_group.platform_management.id
  subscription_id     = "/subscriptions/${azurerm_subscription.management[0].subscription_id}"
}

resource "azurerm_consumption_budget_subscription" "management" {
  count = var.create_management_subscription ? 1 : 0

  name            = "budget-management"
  subscription_id = "/subscriptions/${azurerm_subscription.management[0].subscription_id}"

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
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
    ignore_changes = [time_period]
  }
}
