// Copy to main.bicepparam and fill in. main.bicepparam is gitignored.
using 'main.bicep'

param prefix = 'contoso'

param brownfieldSubscriptionId = '00000000-0000-0000-0000-000000000000'
param brownfieldSubscriptionName = 'demo'

param monthlyBudgetAmount = 20
param budgetAlertEmails = [
  'you@example.com'
]

// Creation is a billing account operation, so it is behind a flag rather than
// implied by a deployment. billingScopeId is only read when this is true.
param createSubscriptions = false
param billingScopeId = ''

// Set once the management subscription exists. The central workspace is
// skipped while this is empty, and its resource ID is what switches the
// DeployIfNotExists assignment in bicep/10-policy on.
param managementSubscriptionId = ''

param location = 'westus2'
