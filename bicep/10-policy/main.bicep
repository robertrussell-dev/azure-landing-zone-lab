// Policy assignments. Eight, each one explainable: six show one effect each and
// two are the subscription baseline.
//
// Scopes are looked up by name from the prefix. Each assignment names its own
// management group, so where the deployment runs only changes who can run it.
//
//   az deployment mg create --management-group-id contoso --location westus2 \
//     --template-file main.bicep --parameters main.bicepparam

targetScope = 'managementGroup'

@description('Same prefix used by bicep/00-management-groups. Management groups are addressed by the names it derives.')
@minLength(2)
@maxLength(10)
param prefix string

@description('Region for the managed identities created by Modify and DeployIfNotExists assignments. The identity location does not constrain where policy applies.')
param location string = 'westus2'

@description('Value the Modify assignment appends as costCenter.')
param costCenterTagValue string = 'lab'

@description('Resource ID of the workspace the DeployIfNotExists assignments target. Empty until bicep/20 creates it, which leaves them out.')
param logAnalyticsWorkspaceId string = ''

@description('Addresses the Service Health alerts in every subscription notify. Empty leaves that assignment out.')
param alertEmails array = []

// Built in definitions. Effects and required roles checked with
// "az policy definition show".
// tenantResourceId, because definitions are tenant level resources.
var definitions = {
  // AuditIfNotExists. Allowed effects: AuditIfNotExists, Disabled. It reads a
  // Defender for Cloud assessment rather than the subnet, so it only reports
  // correctly where Defender is on; modules/subscription-baseline turns it on.
  subnetsNeedNsg: tenantResourceId('Microsoft.Authorization/policyDefinitions', 'e71308d3-144b-4262-b144-efdc3cc90517')

  // Modify. Requires a managed identity holding Contributor.
  addTag: tenantResourceId('Microsoft.Authorization/policyDefinitions', '4f9dc7db-30c1-420c-b61a-e1d640128d26')

  // Deny. No identity required.
  noPublicIpOnNic: tenantResourceId('Microsoft.Authorization/policyDefinitions', '83a86a26-fd1f-447c-b59d-e51f44264114')

  // DeployIfNotExists. Requires an identity holding Log Analytics Contributor
  // and Monitoring Contributor.
  nsgDiagnostics: tenantResourceId('Microsoft.Authorization/policyDefinitions', '98a2e215-5382-489e-bd29-32e7190a39ba')

  // DeployIfNotExists. Same two roles as nsgDiagnostics.
  activityLog: tenantResourceId('Microsoft.Authorization/policyDefinitions', '2465583e-4e78-4c15-b6be-a36cbc7c8b0f')

  // DeployIfNotExists. Requires Monitoring Policy Contributor. Creates a
  // resource group, an action group and an alert rule in each subscription.
  serviceHealth: tenantResourceId('Microsoft.Authorization/policyDefinitions', '98903777-a9f6-47f5-90a9-acaf62ab01a8')

  // DenyAction. No identity required.
  noDelete: tenantResourceId('Microsoft.Authorization/policyDefinitions', '78460a36-508a-49a4-b2b2-2f5ec564f4bb')
}

var roleIds = {
  contributor: tenantResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  logAnalyticsContributor: tenantResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293'
  )
  monitoringContributor: tenantResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
  )
  monitoringPolicyContributor: tenantResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '47be4a87-7950-4631-9daf-b664a405f074'
  )
}

// ---------------------------------------------------------------------------
// Intermediate root: applies to everything
// ---------------------------------------------------------------------------

// Modify. Appends costCenter to resources that lack it.
//
// The built in requires Contributor, not Tag Contributor, so its identity gets
// Contributor across the hierarchy. A custom definition could ask for less.
module appendCostCenterTag '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup(prefix)
  name: 'assign-append-costcenter'
  params: {
    name: 'append-costcenter'
    displayName: 'Append costCenter tag to resources'
    policyDescription: 'Every resource in this lab carries costCenter so spend can be attributed and cleanup can find things. Applied at the intermediate root because it has no archetype specific behavior.'
    policyDefinitionId: definitions.addTag
    location: location
    roleDefinitionIds: [
      roleIds.contributor
    ]
    parameters: {
      tagName: 'costCenter'
      tagValue: costCenterTagValue
    }
  }
}

// AuditIfNotExists at the top of the tree. Reports, never blocks.
module auditSubnetsWithoutNsg '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup(prefix)
  name: 'assign-audit-subnet-nsg'
  params: {
    name: 'audit-subnet-nsg'
    displayName: 'Subnets should be associated with a network security group'
    policyDescription: 'Reported across the whole hierarchy so the platform team can see the shape of the environment. Audit rather than deny at this scope, because a subnet without a network security group is a finding to investigate, not always a mistake.'
    policyDefinitionId: definitions.subnetsNeedNsg
    parameters: {
      effect: 'AuditIfNotExists'
    }
    nonComplianceMessage: 'This subnet has no network security group. Attach one, or record an exemption explaining why it does not need one.'
  }
}

// ---------------------------------------------------------------------------
// Corp archetype only: inheritance is scope dependent
// ---------------------------------------------------------------------------

// Deny at Corp only. Online is meant to have direct internet access.
module denyPublicIpOnNicCorp '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup('${prefix}-lz-corp')
  name: 'assign-deny-nic-public-ip'
  params: {
    name: 'deny-nic-public-ip'
    displayName: 'Network interfaces must not have public IPs'
    policyDescription: 'Corp workloads route to the internet through the hub so egress can be inspected. A public IP on a network interface bypasses that path. Assigned at Corp only. Online does not carry this policy, because direct internet connectivity is what defines that archetype.'
    policyDefinitionId: definitions.noPublicIpOnNic
    nonComplianceMessage: 'Corp workloads cannot have public IPs on network interfaces. Route through the hub, or place this workload under the Online archetype instead.'
  }
}

// ---------------------------------------------------------------------------
// Platform only: things that must not be deleted
// ---------------------------------------------------------------------------

// At Platform, so a future platform workspace is covered too. It doesn't stop a
// resource group delete; the lock in bicep/20 does. ADR 0008 has the reasoning.
module denyPlatformWorkspaceDelete '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup('${prefix}-platform')
  name: 'assign-deny-platform-delete'
  params: {
    name: 'deny-platform-delete'
    displayName: 'Platform Log Analytics workspaces cannot be deleted'
    policyDescription: 'Every activity log and diagnostic setting in the hierarchy sends to the platform workspace, so deleting it silently breaks log collection everywhere. Assigned at Platform so a workspace added to any platform subscription is covered. Bypassed only by an exemption, which needs rights on this assignment, not just on the subscription.'
    policyDefinitionId: definitions.noDelete
    parameters: {
      effect: 'DenyAction'
      listOfResourceTypesDisallowedForDeletion: [
        'Microsoft.OperationalInsights/workspaces'
      ]
    }
    nonComplianceMessage: 'Platform workspaces cannot be deleted. If this really has to go, ask the platform team for a policy exemption with an expiry.'
  }
}

// ---------------------------------------------------------------------------
// Brownfield: the same Deny, evaluated but not enforced
// ---------------------------------------------------------------------------

// The Corp Deny with enforcement off. See ADR 0005.
module denyPublicIpOnNicCorpAudit '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup('${prefix}-lz-corp-audit')
  name: 'assign-deny-nic-public-ip-audit'
  params: {
    name: 'deny-nic-public-ip'
    displayName: 'Network interfaces must not have public IPs (audit only)'
    policyDescription: 'Same policy as Corp, assigned with enforcementMode DoNotEnforce. Subscriptions migrating in are measured against the target policy set without any deny taking effect. Moving the subscription to Corp is what turns enforcement on.'
    policyDefinitionId: definitions.noPublicIpOnNic
    enforce: false
    nonComplianceMessage: 'This would be denied under the Corp archetype. Nothing is blocked here. Remediate before this subscription moves to Corp.'
  }
}

// ---------------------------------------------------------------------------
// DeployIfNotExists: only once there is a workspace to point at
// ---------------------------------------------------------------------------

// Skipped until bicep/20 creates the workspace. Without a target it would
// create an identity with two roles and remediate nothing.
module deployNsgDiagnostics '../modules/policy-assignment/main.bicep' = if (!empty(logAnalyticsWorkspaceId)) {
  scope: managementGroup('${prefix}-platform-management')
  name: 'assign-dine-nsg-diagnostics'
  params: {
    name: 'dine-nsg-diagnostics'
    displayName: 'Deploy diagnostic settings for network security groups'
    policyDescription: 'Network security group logs are routed to the central workspace automatically, so that a workload team forgetting to configure diagnostics does not create a blind spot for the platform team.'
    policyDefinitionId: definitions.nsgDiagnostics
    location: location
    roleDefinitionIds: [
      roleIds.logAnalyticsContributor
      roleIds.monitoringContributor
    ]
    parameters: {
      logAnalytics: logAnalyticsWorkspaceId
    }
  }
}

// ---------------------------------------------------------------------------
// Intermediate root: the subscription baseline
// ---------------------------------------------------------------------------
// Policy, so subscriptions vended later get them too. Existing subscriptions
// need a one off remediation task; the runbook covers it.

// Activity log ingestion into Log Analytics is free.
module deployActivityLog '../modules/policy-assignment/main.bicep' = if (!empty(logAnalyticsWorkspaceId)) {
  scope: managementGroup(prefix)
  name: 'assign-dine-activity-log'
  params: {
    name: 'dine-activity-log'
    displayName: 'Send subscription activity logs to the central workspace'
    policyDescription: 'Every subscription streams its activity log to the platform workspace, so there is one place to answer who changed what, including in subscriptions vended after this was assigned.'
    policyDefinitionId: definitions.activityLog
    location: location
    roleDefinitionIds: [
      roleIds.logAnalyticsContributor
      roleIds.monitoringContributor
    ]
    parameters: {
      logAnalytics: logAnalyticsWorkspaceId
    }
  }
}

// Free: the alert rule, and the first 1,000 emails a month.
module deployServiceHealthAlerts '../modules/policy-assignment/main.bicep' = if (!empty(alertEmails)) {
  scope: managementGroup(prefix)
  name: 'assign-dine-service-health'
  params: {
    name: 'dine-service-health'
    displayName: 'Configure Service Health alerts in every subscription'
    policyDescription: 'Each subscription gets a Service Health alert rule and an action group, so an Azure incident affecting it reaches the platform team rather than being found in the portal afterward.'
    policyDefinitionId: definitions.serviceHealth
    location: location
    roleDefinitionIds: [
      roleIds.monitoringPolicyContributor
    ]
    parameters: {
      resourceGroupName: 'rg-service-health-alerts'
      resourceGroupLocation: location
      actionGroupResources: {
        actionGroupEmail: alertEmails
        eventHubResourceId: []
        functionResourceId: ''
        functionTriggerUrl: ''
        logicappCallbackUrl: ''
        logicappResourceId: ''
        webhookServiceUri: []
      }
    }
  }
}

@description('Policy assignment IDs by short name.')
output assignmentIds object = union(
  {
    appendCostCenterTag: appendCostCenterTag.outputs.id
    auditSubnetsWithoutNsg: auditSubnetsWithoutNsg.outputs.id
    denyPublicIpOnNicCorp: denyPublicIpOnNicCorp.outputs.id
    denyPublicIpOnNicCorpAudit: denyPublicIpOnNicCorpAudit.outputs.id
    denyPlatformWorkspaceDelete: denyPlatformWorkspaceDelete.outputs.id
  },
  empty(logAnalyticsWorkspaceId)
    ? {}
    : {
        deployNsgDiagnostics: deployNsgDiagnostics!.outputs.id
      },
  empty(logAnalyticsWorkspaceId)
    ? {}
    : {
        deployActivityLog: deployActivityLog!.outputs.id
      },
  empty(alertEmails)
    ? {}
    : {
        deployServiceHealthAlerts: deployServiceHealthAlerts!.outputs.id
      }
)

@description('Which policy effect each assignment exercises, for the README.')
output effectsDemonstrated object = {
  Modify: 'append-costcenter, at the intermediate root'
  AuditIfNotExists: 'audit-subnet-nsg, at the intermediate root'
  Deny: 'deny-nic-public-ip, at Corp'
  DoNotEnforce: 'deny-nic-public-ip, at Corp (audit only), same definition, enforcement off'
  DenyAction: 'deny-platform-delete, at Platform'
  DeployIfNotExists: empty(logAnalyticsWorkspaceId)
    ? 'not yet assigned, awaiting the workspace in bicep/20'
    : 'dine-nsg-diagnostics, at Platform Management'
}
