# Subscription vending.
#
# The alias API creates the subscription against a billing scope and the
# platform team places it. Both steps belong to the platform team, and both are
# here.
#
# Billing scope permissions are a separate model from Azure RBAC. Owner on a
# management group grants nothing here. The caller needs Owner, Contributor or
# Azure subscription creator on the invoice section, billing profile or billing
# account. That split is the most common blocker when a team first automates
# this, and the onboarding runbook calls it out.
#
# Placement is the archetype decision from ADR 0003 made concrete: it is what
# determines the policy set and role assignments each subscription inherits.

locals {
  subscriptions = {
    management = {
      display_name        = "sub-management"
      management_group_id = data.azurerm_management_group.platform_management.id
    }
    connectivity = {
      display_name        = "sub-connectivity"
      management_group_id = data.azurerm_management_group.platform_connectivity.id
    }
    corp-payments-prod = {
      display_name        = "sub-corp-payments-prod"
      management_group_id = data.azurerm_management_group.corp.id
    }
    online-portal-prod = {
      display_name        = "sub-online-portal-prod"
      management_group_id = data.azurerm_management_group.online.id
    }
  }
}

module "subscription" {
  source   = "../../modules/subscription-vending"
  for_each = var.create_subscriptions ? local.subscriptions : {}

  display_name        = each.value.display_name
  billing_scope_id    = var.billing_scope_id
  management_group_id = each.value.management_group_id

  budget_amount         = var.monthly_budget_amount
  budget_contact_emails = var.budget_alert_emails

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }
}

# The management subscription predates the move to for_each. Without these the
# refactor reads as destroy and create, and destroying azurerm_subscription
# cancels a live subscription.
moved {
  from = module.management_subscription[0].azurerm_subscription.this
  to   = module.subscription["management"].azurerm_subscription.this
}

moved {
  from = module.management_subscription[0].azurerm_management_group_subscription_association.this
  to   = module.subscription["management"].azurerm_management_group_subscription_association.this
}

moved {
  from = module.management_subscription[0].module.budget.azurerm_consumption_budget_subscription.this
  to   = module.subscription["management"].module.budget.azurerm_consumption_budget_subscription.this
}
