// Copy to main.bicepparam and fill in. main.bicepparam is gitignored.
//
// The brownfield subscription is not a parameter. It is the deployment scope,
// so it is passed as --subscription on the command line. See main.bicep.
using 'main.bicep'

param location = 'westus2'
