# Subscription vending: create a subscription, place it, budget it.
#
# This is the platform capability an application team consumes. Everything a
# new landing zone needs that can be done from outside the subscription is here
# in one call.
#
# What is deliberately NOT here, and why, is in the README: resources inside
# the new subscription cannot be created in the same apply that creates it,
# because a provider cannot be configured for a subscription ID that does not
# exist at plan time. That is a Terraform limitation, not a design choice, and
# pretending otherwise produces a module that works once and fails on rebuild.

resource "azurerm_subscription" "this" {
  subscription_name = var.display_name

  # The alias is the name of the alias object, not of the subscription, and it
  # is immutable. Reusing an alias name that already exists adopts the existing
  # subscription rather than creating a second one, which is occasionally what
  # you want and more often a surprise.
  alias            = var.alias == null ? var.display_name : var.alias
  billing_scope_id = var.billing_scope_id
  workload         = var.workload

  tags = var.tags

  lifecycle {
    # Destroying this resource cancels the subscription. Cancellation is
    # recoverable for a limited window, but a terraform destroy that silently
    # cancels a live subscription is not a failure mode worth leaving open.
    # Decommissioning is a deliberate act performed outside this workflow, and
    # the Decommissioned management group exists for the subscriptions it
    # produces.
    prevent_destroy = true
  }
}

# Subscriptions created through the alias API land in the tenant root
# management group. Placement is always a second operation, never part of
# creation, and it is what determines the policy and role assignments the
# subscription inherits.
#
# Place before deploying anything into the subscription. A subscription whose
# authorization is inherited from a management group behaves differently from
# one relying solely on the assignment created at vending time. See the
# onboarding runbook.
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
