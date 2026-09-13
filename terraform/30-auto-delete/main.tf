# The janitor: an Automation runbook that deletes billable devices once the
# deleteAfter tag set by terraform/90-optional-network has passed. The runbook is
# automation/Remove-ExpiredResources.ps1, shared with the Bicep tree.
#
# A budget can't do this: it only notifies, and cost data lags by hours.

resource "azurerm_resource_group" "automation" {
  provider = azurerm.management

  name     = "rg-management-automation"
  location = var.location

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }
}

resource "azurerm_automation_account" "janitor" {
  provider = azurerm.management

  # checkov:skip=CKV2_AZURE_24:Left on until a test shows scheduled cloud jobs
  # still run with it off, which Microsoft doesn't document. Local auth is off,
  # so the endpoint has no key or webhook to accept.

  name                = "aa-${var.prefix}-auto-delete"
  resource_group_name = azurerm_resource_group.automation.name
  location            = azurerm_resource_group.automation.location
  sku_name            = "Basic"

  # Webhooks and agent keys. The runbook uses the managed identity.
  local_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }
}

# Windows PowerShell 5.1, which needs no runtime environment. The runbook
# imports no modules.
resource "azurerm_automation_runbook" "remove_expired" {
  provider = azurerm.management

  name                    = "Remove-ExpiredResources"
  description             = "Deletes billable devices tagged autoDelete = true whose deleteAfter has passed."
  resource_group_name     = azurerm_resource_group.automation.name
  location                = azurerm_resource_group.automation.location
  automation_account_name = azurerm_automation_account.janitor.name
  runbook_type            = "PowerShell"
  content                 = file("${path.module}/../../automation/Remove-ExpiredResources.ps1")

  log_progress = false
  log_verbose  = false

  tags = {
    costCenter = "lab"
    autoDelete = "false"
  }
}

# start_time is left to the provider, which sets it a few minutes ahead at
# creation. Computing it here would change on every plan.
resource "azurerm_automation_schedule" "every_interval" {
  provider = azurerm.management

  name                    = "auto-delete"
  description             = "Runs Remove-ExpiredResources every ${var.run_interval_hours} hours."
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.janitor.name
  frequency               = "Hour"
  interval                = var.run_interval_hours
  timezone                = "Etc/UTC"
}

resource "azurerm_automation_job_schedule" "remove_expired" {
  provider = azurerm.management

  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.janitor.name
  runbook_name            = azurerm_automation_runbook.remove_expired.name
  schedule_name           = azurerm_automation_schedule.every_interval.name

  # The provider requires lowercase keys. PowerShell matches parameter names
  # case insensitively.
  parameters = {
    managementgroupid = var.prefix
  }
}
