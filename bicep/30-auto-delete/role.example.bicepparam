// Copy to role.bicepparam and fill in. role.bicepparam is gitignored.
//
// janitorPrincipalId is not set here. It comes from the auto-delete stack's
// output and is passed on the command line; see the header of main.bicep.
using 'role.bicep'

param prefix = 'contoso'
param janitorPrincipalId = ''
