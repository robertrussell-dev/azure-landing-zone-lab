# The per subscription baseline that Azure Policy cannot apply: resource
# provider registration and Defender for Cloud's free posture tier. The rest of
# the baseline, activity log streaming and Service Health alerts, is policy in
# terraform/10-policy, because policy reaches every subscription under the
# intermediate root including ones vended later.
#
# Everything here goes through azapi rather than azurerm. azurerm registers
# providers and sets Defender plans only in the subscription its provider block
# points at, and a provider block cannot be created per subscription in a loop.
# azapi addresses any subscription by resource ID, so one module serves them all.
#
# Everything here is free.

# A new subscription has almost nothing registered, and anything that needs an
# unregistered provider fails with MissingSubscriptionRegistration. Only the
# providers the platform itself uses are registered: Microsoft recommends
# against registering what nothing needs.
resource "azapi_resource_action" "register" {
  for_each = toset(var.resource_providers)

  type        = "Microsoft.Resources/providers@2021-04-01"
  resource_id = "/subscriptions/${var.subscription_id}/providers/${each.value}"
  action      = "register"
  method      = "POST"
}

# Registration is asynchronous: the call returns while the provider is still
# registering. Writing a Defender setting in that window fails.
resource "time_sleep" "registration" {
  depends_on      = [azapi_resource_action.register]
  create_duration = "60s"
}

# Foundational CSPM, the free tier of Defender for Cloud posture management.
# From 27 October 2026 new subscriptions no longer get it by default, so it is
# set explicitly. "Free" here is the free plan; "Standard" would be the paid
# Defender CSPM plan, billed per resource.
#
# azapi_update_resource rather than azapi_resource: the pricing object exists as
# soon as Microsoft.Security is registered and cannot be deleted, so this
# updates it in place and leaves it alone on destroy.
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

# Who Defender emails about high severity alerts in this subscription, in
# addition to its owners.
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
