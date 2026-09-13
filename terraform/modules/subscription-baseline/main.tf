# The part of the subscription baseline policy can't do: provider registration
# and Defender for Cloud's free tier. The rest is policy in terraform/10-policy.
# All free.
#
# azapi, because azurerm only acts on its provider's subscription and providers
# can't be created in a loop. azapi takes any subscription by resource ID.

# Only the providers the platform uses. Microsoft advises against registering
# the rest.
resource "azapi_resource_action" "register" {
  for_each = toset(var.resource_providers)

  type        = "Microsoft.Resources/providers@2021-04-01"
  resource_id = "/subscriptions/${var.subscription_id}/providers/${each.value}"
  action      = "register"
  method      = "POST"
}

# Registration is asynchronous, and Defender writes fail until it finishes.
resource "time_sleep" "registration" {
  depends_on      = [azapi_resource_action.register]
  create_duration = "60s"
}

# Foundational CSPM. From 27 October 2026 new subscriptions no longer get it by
# default. "Standard" would be the paid plan.
#
# An update, because the pricing object always exists and can't be deleted.
resource "azapi_update_resource" "foundational_cspm" {
  type      = "Microsoft.Security/pricings@2024-01-01"
  name      = "CloudPosture"
  parent_id = "/subscriptions/${var.subscription_id}"

  body = {
    properties = {
      pricingTier = "Free"
    }
  }

  depends_on = [time_sleep.registration]
}

# Who Defender emails about high severity alerts, besides the owners.
resource "azapi_resource" "security_contact" {
  count = length(var.security_contact_emails) > 0 ? 1 : 0

  type      = "Microsoft.Security/securityContacts@2023-12-01-preview"
  name      = "default"
  parent_id = "/subscriptions/${var.subscription_id}"

  body = {
    properties = {
      emails    = join(";", var.security_contact_emails)
      isEnabled = true
      notificationsByRole = {
        state = "On"
        roles = ["Owner"]
      }
      notificationsSources = [
        {
          sourceType      = "Alert"
          minimalSeverity = "High"
        }
      ]
    }
  }

  depends_on = [time_sleep.registration]
}
