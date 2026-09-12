// The resource group that holds the central workspace, in the management
// subscription.
//
// This file exists to change scope. main.bicep is a tenant deployment and a
// resource group is a subscription level resource, so the resource group is
// created here and the workspace inside it is created one scope further down,
// in log-analytics-workspace.bicep. Passing the resource group symbol as the
// module scope is what carries the dependency.

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
    autoDelete: 'true'
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
