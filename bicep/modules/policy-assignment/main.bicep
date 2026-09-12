// One policy assignment at management group scope, plus the role assignments its
// managed identity needs.
//
// The Bicep counterpart of modules/policy-assignment. Same five callers, same
// shape, same rule: passing roleDefinitionIds is what switches identity
// creation on, so an Audit assignment never grows an identity with nothing to
// do.
//
// Effects that need an identity:
//   Modify              needs the roles that let it write the change
//   DeployIfNotExists   needs the roles that let it deploy the remediation
// Effects that do not:
//   Audit, AuditIfNotExists, Deny, Disabled
//
// This module is deployed into the management group it assigns at, so the
// caller sets the target through the module's scope property rather than by
// passing an ID. That is the one structural difference from the Terraform
// module, which takes management_group_id as a variable.

targetScope = 'managementGroup'

@description('Assignment name. Becomes part of the resource ID, so it is immutable. Azure limits this to 24 characters at management group scope.')
@maxLength(24)
param name string

@description('Human readable name shown in the portal compliance view.')
param displayName string

// Not called "description". A parameter of that name shadows the @description
// decorator for the rest of the file, and every decorator below it fails to
// compile with an error that names the decorator rather than the parameter.
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

// Built in definitions are versioned, and an assignment can pin which versions
// it tracks: '1.*.*' follows the latest 1.x, '1.2.0' pins exactly. Azure sets
// this itself when the assignment does not, which is why the assignments the
// Terraform tree created carry '1.*.*' and '3.*.*' without anything in that
// configuration asking for them.
//
// Left empty by default rather than guessed. Setting it on a definition that
// is not versioned is an error, and the value that is right for one definition
// is not right for another.
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

    // DoNotEnforce still evaluates and reports compliance, the effect simply
    // does not act. This is what makes an audit only brownfield assignment
    // possible without touching workloads.
    enforcementMode: enforce ? 'Default' : 'DoNotEnforce'

    // Azure expects {"paramName": {"value": x}}. Callers pass a flat object and
    // the module does the wrapping, so call sites stay readable. toObject with
    // two lambdas is the Bicep equivalent of the Terraform for expression.
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

// No wait before the role assignment, and that is the interesting difference
// from the Terraform module.
//
// The managed identity is created with the assignment and Microsoft Entra takes
// time to replicate it, so a role assignment created immediately afterwards can
// fail with PrincipalNotFound. Terraform needs an explicit time_sleep for this.
// ARM does not: setting principalType tells the RBAC service the principal is a
// service principal that may not have replicated yet, and it retries instead of
// failing. The property needs apiVersion 2018-09-01-preview or later, and
// 2022-04-01 is the first stable version that carries it.
//
// https://learn.microsoft.com/azure/role-based-access-control/troubleshooting#azure-role-assignments
resource identityRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleDefinitionId in roleDefinitionIds: if (needsIdentity) {
    // Role assignment names must be GUIDs and must be deterministic, or a
    // redeploy creates a second assignment instead of matching the first.
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
