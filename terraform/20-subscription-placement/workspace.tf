# Central Log Analytics workspace, in the management subscription. The
# DeployIfNotExists assignments in terraform/10-policy send diagnostics here.
#
# Ingestion is 2.30 USD per GB and retention past 31 days is 0.10 per GB per
# month (retail prices API, West US 2, 2026-09-06). The 0.1 GB daily cap limits
# the worst case to about 7 USD a month.

resource "azurerm_resource_group" "management_logs" {
  provider = azurerm.management
  count    = var.create_subscriptions ? 1 : 0

  name     = "rg-management-logs"
  location = var.location

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }
}

# The DenyAction policy in terraform/10-policy doesn't block a resource group
# delete, so this lock covers that path. ADR 0008 has the details.
resource "azurerm_management_lock" "management_logs" {
  provider = azurerm.management
  count    = var.create_subscriptions ? 1 : 0

  name       = "lock-management-logs"
  scope      = azurerm_resource_group.management_logs[0].id
  lock_level = "CanNotDelete"
  notes      = "Holds the platform workspace every activity log and diagnostic setting points at. See ADR 0008."
}

resource "azurerm_log_analytics_workspace" "management" {
  provider = azurerm.management
  count    = var.create_subscriptions ? 1 : 0

  name                = "law-${var.prefix}-management"
  resource_group_name = azurerm_resource_group.management_logs[0].name
  location            = azurerm_resource_group.management_logs[0].location

  sku = "PerGB2018"

  # The minimum, and free. Longer retention is billed per GB.
  retention_in_days = 30

  # Ingestion stops for the day once hit and resumes at the daily reset.
  daily_quota_gb = 0.1

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }
}
