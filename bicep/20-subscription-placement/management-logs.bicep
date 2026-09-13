// The resource group for the central workspace. A separate file because
// main.bicep is tenant scoped and a resource group is a subscription resource.

targetScope = 'subscription'

@description('Same prefix used by bicep/00-management-groups. Part of the workspace name.')
param prefix string

@description('Region for the resource group and the workspace.')
param location string

resource managementLogs 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-management-logs'
  location: location
  tags: {
    costCenter: 'lab'
    autoDelete: 'false'
  }
}

module workspace 'log-analytics-workspace.bicep' = {
  scope: managementLogs
  name: 'law-${prefix}-management'
  params: {
    name: 'law-${prefix}-management'
    location: location
  }
}

@description('Resource ID of the central workspace.')
output workspaceId string = workspace.outputs.id
