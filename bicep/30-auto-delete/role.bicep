// The janitor's role. Network Contributor would let a mistagged hub network be
// deleted, so this deletes only the six types the runbook lists. Keep the two in
// step. Not yet exercised by a real delete.
//
// Its own stack, because deny settings can't cover management group resources.
// Commands are in main.bicep.

targetScope = 'managementGroup'

@description('Same prefix used by bicep/00-management-groups. Part of the role name.')
@minLength(2)
@maxLength(10)
param prefix string

@description('Object ID of the janitor\'s managed identity, from the janitorPrincipalId output of the auto-delete stack.')
param janitorPrincipalId string

// Fixed, so this and the Terraform tree define the same role.
var janitorRoleId = '0c8d0f7e-026b-451b-a195-3f78e7c8ab4a'

resource janitorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: janitorRoleId
  properties: {
    roleName: '${prefix} auto delete janitor'
    description: 'Find resources through Resource Graph and delete billable network devices. Nothing else.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Resources/subscriptions/read'
          'Microsoft.Resources/subscriptions/resourceGroups/read'
          'Microsoft.Network/*/read'
          'Microsoft.Network/azureFirewalls/delete'
          'Microsoft.Network/virtualNetworkGateways/delete'
          'Microsoft.Network/bastionHosts/delete'
          'Microsoft.Network/virtualHubs/delete'
          'Microsoft.Network/virtualHubs/ipConfigurations/delete'
          'Microsoft.Network/firewallPolicies/delete'
          'Microsoft.Network/publicIPAddresses/delete'
        ]
        notActions: []
      }
    ]
    assignableScopes: [
      managementGroup().id
    ]
  }
}

// At the management group, because billable devices can be in any subscription.
resource janitorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managementGroup().id, janitorRoleId, janitorPrincipalId)
  properties: {
    roleDefinitionId: janitorRole.id
    principalId: janitorPrincipalId
    principalType: 'ServicePrincipal'
  }
}
