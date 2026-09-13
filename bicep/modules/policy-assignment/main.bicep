// One policy assignment at management group scope, plus the role assignments its
// managed identity needs.
//
// Passing roleDefinitionIds switches identity creation on, so an Audit
// assignment never gets an identity it doesn't use.
//
// Effects that need an identity:
//   Modify              needs the roles that let it write the change
//   DeployIfNotExists   needs the roles that let it deploy the remediation
// Effects that do not:
//   Audit, AuditIfNotExists, Deny, DenyAction, Disabled
//
// The caller picks the management group through the module's scope. The
// Terraform module takes it as a variable instead.

targetScope = 'managementGroup'

@description('Assignment name. Becomes part of the resource ID, so it is immutable. Azure limits this to 24 characters at management group scope.')
@maxLength(24)
param name string

@description('Human readable name shown in the portal compliance view.')
param displayName string

// Not "description", which would shadow the @description decorator.
@description('Why this policy is assigned here. Shown to anyone who hits it, so write it for them.')
param policyDescription string

@description('Full resource ID of the policy definition or initiative.')
param policyDefinitionId string

@description('Policy parameters as a flat object. The module wraps each value in the {value: x} shape Azure expects.')
param parameters object = {}

@description('true assigns with enforcementMode Default. false assigns with DoNotEnforce, which evaluates compliance and reports it but does not act on the effect. false is the brownfield audit only pattern.')
param enforce bool = true

@description('Role definition IDs the assignment\'s managed identity needs. Required for Modify and DeployIfNotExists effects, empty for Audit and Deny. Read these off the definition\'s policyRule.then.details.roleDefinitionIds rather than guessing.')
param roleDefinitionIds array = []

@description('Region for the system assigned managed identity. Required whenever roleDefinitionIds is non empty, ignored otherwise.')
param location string = ''

@description('Message shown when a resource fails this policy. Empty falls back to Azure\'s generic text, which tells the reader nothing.')
param nonComplianceMessage string = ''

// Empty by default. Setting it on an unversioned definition is an error. See
// the README.
@description('Definition version this assignment tracks, for example 1.*.* or 1.2.0. Empty lets Azure apply its own default, which is the major version of the definition at assignment time.')
param definitionVersion string = ''

var needsIdentity = !empty(roleDefinitionIds)

resource assignment 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: name

  // A system assigned identity requires a location. Azure rejects the
  // assignment if an identity is declared without one.
  location: needsIdentity ? location : null
  identity: needsIdentity ? { type: 'SystemAssigned' } : { type: 'None' }

  properties: {
    displayName: displayName
    description: policyDescription
    policyDefinitionId: policyDefinitionId
    definitionVersion: empty(definitionVersion) ? null : definitionVersion

    // DoNotEnforce still evaluates and reports; the effect doesn't act.
    enforcementMode: enforce ? 'Default' : 'DoNotEnforce'

    // Azure expects {"paramName": {"value": x}}; callers pass a flat object.
    parameters: toObject(items(parameters), parameter => parameter.key, parameter => { value: parameter.value })

    nonComplianceMessages: empty(nonComplianceMessage)
      ? []
      : [
          {
            message: nonComplianceMessage
          }
        ]
  }
}

// No replication wait, unlike the Terraform module. principalType tells RBAC
// the principal may not have replicated yet, so it retries. See the README.
// https://learn.microsoft.com/azure/role-based-access-control/troubleshooting#azure-role-assignments
resource identityRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleDefinitionId in roleDefinitionIds: if (needsIdentity) {
    // A stable GUID, so a redeploy matches the existing assignment.
    name: guid(managementGroup().id, name, roleDefinitionId)
    properties: {
      roleDefinitionId: roleDefinitionId
      principalId: assignment.identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

@description('Resource ID of the policy assignment.')
output id string = assignment.id

@description('Object ID of the assignment\'s managed identity, or an empty string if the effect does not need one.')
output principalId string = needsIdentity ? assignment.identity.principalId : ''
