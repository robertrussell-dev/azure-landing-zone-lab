// The Automation account, the runbook, and the schedule that runs it. None of
// them bill; jobs are inside Automation's free 500 minutes a month.

@description('Account name.')
param name string

@description('Region.')
param location string

@description('Hours between runs.')
param runIntervalHours int

@description('Where Automation downloads the runbook from.')
param runbookContentUri string

@description('When the schedule first fires.')
param scheduleStart string

@description('Management group the runbook searches.')
param managementGroupName string

@description('Tags applied to every resource.')
param tags object

resource account 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: name
  location: location
  tags: tags

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    sku: {
      name: 'Basic'
    }

    // Webhooks and agent keys. The runbook uses the managed identity.
    disableLocalAuth: true
  }
}

// Windows PowerShell 5.1, which needs no runtime environment. ARM has no inline
// runbook content, only a URL Automation downloads from, so pin it to a commit.
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: account
  name: 'Remove-ExpiredResources'
  location: location
  tags: tags
  properties: {
    description: 'Deletes billable devices tagged autoDelete = true whose deleteAfter has passed.'
    runbookType: 'PowerShell'
    logProgress: false
    logVerbose: false
    publishContentLink: {
      uri: runbookContentUri
    }
  }
}

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = {
  parent: account
  name: 'auto-delete'
  properties: {
    description: 'Runs Remove-ExpiredResources every ${runIntervalHours} hours.'
    frequency: 'Hour'
    interval: runIntervalHours
    startTime: scheduleStart
    timeZone: 'Etc/UTC'
  }
}

// The name must be a GUID, and a stable one, or each deployment links the
// runbook again. Redeploys are untested; check here first if one fails.
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2024-10-23' = {
  parent: account
  name: guid(account.id, runbook.name, schedule.name)
  properties: {
    runbook: {
      name: runbook.name
    }
    schedule: {
      name: schedule.name
    }
    parameters: {
      ManagementGroupId: managementGroupName
    }
  }
}

@description('Resource ID of the account.')
output id string = account.id

@description('Object ID of the account\'s system assigned managed identity.')
output principalId string = account.identity.principalId
