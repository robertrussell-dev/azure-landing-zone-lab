# Subscription placement and cost guardrails.
#
# The alias API creates a subscription at the tenant root and it's moved
# afterward, so creation and placement are separate resources here too.

data "azurerm_management_group" "corp_audit" {
  name = "${var.prefix}-lz-corp-audit"
}

data "azurerm_management_group" "platform_management" {
  name = "${var.prefix}-platform-management"
}

data "azurerm_management_group" "platform_connectivity" {
  name = "${var.prefix}-platform-connectivity"
}

data "azurerm_management_group" "corp" {
  name = "${var.prefix}-lz-corp"
}

data "azurerm_management_group" "online" {
  name = "${var.prefix}-lz-online"
}

# ---------------------------------------------------------------------------
# Brownfield placement
# ---------------------------------------------------------------------------
# DemoSubscription predates the landing zone, so it goes under Corp (audit
# only). Moving it to Corp turns enforcement on. See ADR 0005.
resource "azurerm_management_group_subscription_association" "brownfield" {
  management_group_id = data.azurerm_management_group.corp_audit.id
  subscription_id     = "/subscriptions/${var.brownfield_subscription_id}"
}

