// The janitor: an Automation runbook that deletes billable devices once their
// deleteAfter tag has passed. The runbook is automation/Remove-ExpiredResources.ps1,
// shared with terraform/30-auto-delete.
//
// Deployed as two stacks, for the reasons in ADR 0008. This file is the
// account, runbook and schedule, with denyDelete. role.bicep is the role and
// its assignment, with no deny settings.
//
//   az stack mg create --name auto-delete \
//     --management-group-id contoso-platform-management \
//     --deployment-subscription <management GUID> --location westus2 \
//     --template-file main.bicep --parameters main.bicepparam \
//     --action-on-unmanage deleteAll --deny-settings-mode denyDelete
//
//   PRINCIPAL=$(az stack mg show --name auto-delete \
//     --management-group-id contoso-platform-management \
//     --query outputs.janitorPrincipalId.value -o tsv)
//
//   az stack mg create --name auto-delete-role --management-group-id contoso \
//     --location westus2 --template-file role.bicep \
//     --parameters role.bicepparam --parameters janitorPrincipalId=$PRINCIPAL \
//     --action-on-unmanage deleteAll --deny-settings-mode none
//
// Destroy, role first:
//
//   az stack mg delete --name auto-delete-role --management-group-id contoso \
//     --action-on-unmanage deleteAll
//   az stack mg delete --name auto-delete \
//     --management-group-id contoso-platform-management \
//     --action-on-unmanage deleteAll

targetScope = 'subscription'

@description('Same prefix used by bicep/00-management-groups. Part of the account name.')
@minLength(2)
@maxLength(10)
param prefix string

@description('Management group the runbook searches. Normally the intermediate root, and the same scope role.bicep assigns the janitor role at.')
param managementGroupName string

@description('Region for the resource group and the Automation account.')
param location string = 'westus2'

@description('Hours between runs. Automation includes 500 job minutes a month free, and every 2 hours is at most 372 runs a month, inside the allowance even if each is billed as a full minute. Hourly would not be.')
@minValue(2)
@maxValue(24)
param runIntervalHours int = 2

@description('Where Automation downloads the runbook from. ARM has no inline runbook content, so this is a URL. Pin it to a commit rather than a branch.')
param runbookContentUri string

// utcNow is only allowed as a parameter default. Automation rejects a schedule
// that starts in the past, so the first run is 15 minutes out.
@description('Deployment time. Leave unset.')
param deployedAt string = utcNow('u')

var tags = {
  costCenter: 'lab'
  autoDelete: 'false'
}

resource automationGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-management-automation'
  location: location
  tags: tags
}

module account 'automation-account.bicep' = {
  scope: automationGroup
  name: 'aa-${prefix}-auto-delete'
  params: {
    name: 'aa-${prefix}-auto-delete'
    location: location
    runIntervalHours: runIntervalHours
    runbookContentUri: runbookContentUri
    scheduleStart: dateTimeAdd(deployedAt, 'PT15M')
    managementGroupName: managementGroupName
    tags: tags
  }
}

@description('Resource ID of the Automation account that runs the janitor.')
output automationAccountId string = account.outputs.id

@description('Object ID of the janitor\'s managed identity. role.bicep assigns the janitor role to it.')
output janitorPrincipalId string = account.outputs.principalId
