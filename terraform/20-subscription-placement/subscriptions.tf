# Subscription vending.
#
# Creating a subscription needs a billing role on the invoice section, billing
# profile or account; Azure RBAC grants nothing there. The onboarding runbook
# covers it. Placement follows ADR 0003.
#
# vend = false keeps a planned subscription in the map without creating it.

locals {
  subscriptions = {
    management = {
      display_name        = "sub-management"
      management_group_id = data.azurerm_management_group.platform_management.id
      vend                = true
    }
    connectivity = {
      display_name        = "sub-connectivity"
      management_group_id = data.azurerm_management_group.platform_connectivity.id
      vend                = true
    }
    corp-payments-prod = {
      display_name        = "sub-corp-payments-prod"
      management_group_id = data.azurerm_management_group.corp.id
      vend                = false
    }
    online-portal-prod = {
      display_name        = "sub-online-portal-prod"
      management_group_id = data.azurerm_management_group.online.id
      vend                = true
    }
  }
}

module "subscription" {
  source   = "../modules/subscription-vending"
  for_each = var.create_subscriptions ? { for key, sub in local.subscriptions : key => sub if sub.vend } : {}

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
