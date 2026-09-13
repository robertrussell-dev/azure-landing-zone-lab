// Central Log Analytics workspace. The DeployIfNotExists assignments in
// bicep/10-policy send diagnostics here.
//
// Ingestion is 2.30 USD per GB and retention past 31 days is 0.10 per GB per
// month (retail prices API, West US 2, 2026-09-06). The 0.1 GB daily cap limits
// the worst case to about 7 USD a month.

@description('Workspace name.')
param name string

@description('Region for the workspace.')
param location string

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: name
  location: location

  properties: {
    sku: {
      name: 'PerGB2018'
    }

    // The minimum, and free. Longer retention is billed per GB.
    retentionInDays: 30

    workspaceCapping: {
      // Ingestion stops for the day once hit. json() because Bicep has no
      // float literal.
      dailyQuotaGb: json('0.1')
    }
  }

  tags: {
    costCenter: 'lab'
    autoDelete: 'false'
  }
}

// Locks the resource group, which the DenyAction policy doesn't cover. ADR 0008
// has the details. It's here, with no scope, because declaring it from
// management-logs.bicep fails with BCP139.
resource groupLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'lock-management-logs'
  properties: {
    level: 'CanNotDelete'
    notes: 'Holds the platform workspace every activity log and diagnostic setting points at. See ADR 0008.'
  }
}

@description('Resource ID of the workspace.')
output id string = workspace.id
