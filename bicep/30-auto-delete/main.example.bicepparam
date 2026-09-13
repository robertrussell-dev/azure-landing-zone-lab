// Copy to main.bicepparam and fill in. main.bicepparam is gitignored.
//
// Deployed as a stack at the intermediate root, not with az deployment, and
// the management subscription is --deployment-subscription on the command
// line, not a parameter. The commands are in the header of main.bicep.
using 'main.bicep'

param prefix = 'contoso'
param managementGroupName = 'contoso'
param location = 'westus2'
param runIntervalHours = 2

// Replace main with the commit SHA you reviewed. A branch URL publishes
// whatever the branch holds at the moment the stack deploys, and nothing in
// this deployment would notice it had changed.
param runbookContentUri = 'https://raw.githubusercontent.com/robertrussell-dev/azure-landing-zone-lab/main/automation/Remove-ExpiredResources.ps1'
