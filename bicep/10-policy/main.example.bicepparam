// Copy to main.bicepparam and fill in. main.bicepparam is gitignored.
using 'main.bicep'

param prefix = 'contoso'
param location = 'westus2'
param costCenterTagValue = 'lab'

// Leave empty until the Log Analytics workspace exists in the management
// subscription. The DeployIfNotExists assignment is skipped while it is empty.
// bicep/20-subscription-placement outputs the ID once it has created one.
param logAnalyticsWorkspaceId = ''
