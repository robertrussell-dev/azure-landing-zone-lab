# Central Log Analytics workspace, in the management subscription.
#
# This exists so the DeployIfNotExists assignment in terraform/10-policy has
# somewhere to route diagnostics. Until it exists, that assignment is skipped
# rather than assigned against nothing. See terraform/10-policy/main.tf.
#
# Cost, verified against the Azure retail prices API on 2026-09-06 for West
# US 2 in USD. Verify before reusing, these move.
#
#   Analytics Logs Data Ingestion   2.30 per GB
#   Analytics Logs Data Retention   0.10 per GB per month, beyond the
#                                   31 days included at no charge
#
# The daily cap is the guardrail that makes this safe to leave running on a
# personal card. At 0.1 GB per day the worst case is roughly 7 USD per month
# even if something starts logging aggressively, and the realistic figure for a
# lab with no traffic is close to zero. A workspace without a cap is an
# unbounded bill, which is the one shape of mistake worth engineering against.

resource "azurerm_resource_group" "management_logs" {
  provider = azurerm.management
  count    = var.create_subscriptions ? 1 : 0

  name     = "rg-management-logs"
  location = var.location

  tags = {
    costCenter = "lab"
    autoDelete = "true"
  }
}

resource "azurerm_log_analytics_workspace" "management" {
  provider = azurerm.management
  count    = var.create_subscriptions ? 1 : 0

  name                = "law-${var.prefix}-management"
  resource_group_name = azurerm_resource_group.management_logs[0].name
  location            = azurerm_resource_group.management_logs[0].location

  sku = "PerGB2018"

  # 30 days is the minimum and is included at no additional charge. Anything
  # longer is a per GB per month cost and should be a deliberate decision tied
  # to a retention requirement, not a default nobody revisited.
  retention_in_days = 30

  # Ingestion stops for the rest of the day once this is hit. Data already
  # ingested is queryable, and collection resumes at the next daily reset.
  # Losing a lab's logs is preferable to an unbounded bill.
  daily_quota_gb = 0.1

  tags = {
    costCenter = "lab"
    autoDelete = "true"
  }
}
