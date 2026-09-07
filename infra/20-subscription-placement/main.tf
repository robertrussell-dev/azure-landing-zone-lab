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

