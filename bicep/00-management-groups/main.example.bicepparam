// Copy to main.bicepparam and fill in. main.bicepparam is gitignored.
//
// There is no tenant_id or subscription_id here, unlike the Terraform tfvars.
// The scope of a Bicep deployment comes from the command line and the signed in
// context, not from the file, so check "az account show --query tenantId"
// before deploying rather than pinning it in configuration.
using 'main.bicep'

// The prefix becomes part of each management group ID and cannot be changed
// afterwards without recreating the hierarchy. Choose it once, deliberately.
param prefix = 'alz'
param intermediateRootDisplayName = 'ALZ Lab'
