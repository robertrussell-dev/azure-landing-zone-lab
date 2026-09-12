// Policy assignments.
//
// Deliberately a small set. Seven assignments that can each be explained beat
// the full Azure landing zone default set, which is hundreds of policies nobody
// in this repo could defend individually. Five each show one policy effect; the
// last two are the subscription baseline.
//
// Scopes are resolved by name, not by reading the output of another deployment.
// The management group names are deterministic, derived from the same prefix,
// so nothing needs to be passed between root modules and each directory
// deploys independently. That is the same choice the Terraform version makes,
// and it costs the same thing: a wrong prefix fails at deployment time rather
// than at compile time.
//
// Scope. This is a management group deployment, run at the intermediate root:
//
//   az deployment mg create --management-group-id contoso --location westus2 \
//     --template-file main.bicep --parameters main.bicepparam
//
// Each assignment names its own management group explicitly, so pointing the
// CLI somewhere else in the tree changes who is allowed to run it and nothing
// about what gets assigned where.

targetScope = 'managementGroup'

@description('Same prefix used by bicep/00-management-groups. Management groups are addressed by the names it derives.')
@minLength(2)
@maxLength(10)
param prefix string

@description('Region for the managed identities created by Modify and DeployIfNotExists assignments. The identity location does not constrain where policy applies.')
param location string = 'westus2'

@description('Value the Modify assignment appends as costCenter.')
param costCenterTagValue string = 'lab'

@description('Full resource ID of the workspace the DeployIfNotExists assignment targets. Empty until bicep/20 creates it, which leaves that assignment out of the deployment. See the README for why this is sequenced that way.')
param logAnalyticsWorkspaceId string = ''

@description('Addresses the Service Health alerts in every subscription notify. Empty leaves that assignment out.')
param alertEmails array = []

// Built in definition IDs, read from the platform rather than typed from
// memory. Effects and required roles were verified with
// "az policy definition show" before use, because a definition's allowed
// effects are not guessable. Notably the subnet NSG definition permits only
// AuditIfNotExists or Disabled, so it cannot be the Deny example that landing
// zone write ups often claim it is.
//
// Built in definitions are tenant level resources, so tenantResourceId builds
// the same /providers/Microsoft.Authorization/... string the Terraform version
// spells out by hand, and will not silently produce a management group scoped
// ID if this file is ever deployed from somewhere else in the tree.
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
// Security note worth stating rather than burying: this built in requires its
// managed identity to hold Contributor, not Tag Contributor. Assigning it here
// grants a policy created service principal Contributor across the whole
// hierarchy. Tag Contributor would be sufficient for what the policy actually
// does, but the required role list belongs to the definition and is not
// something the assignment can narrow. A custom definition asking only for Tag
// Contributor is the tighter option.
module appendCostCenterTag '../modules/policy-assignment/main.bicep' = {
  scope: managementGroup(prefix)
  name: 'assign-append-costcenter'
  params: {
    name: 'append-costcenter'
    displayName: 'Append costCenter tag to resources'
    policyDescription: 'Every resource in this lab carries costCenter so spend can be attributed and cleanup can find things. Applied at the intermediate root because it has no archetype specific behaviour.'
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
    policyDescription: 'Reported across the whole hierarchy so the platform team can see the shape of the estate. Audit rather than deny at this scope, because a subnet without a network security group is a finding to investigate, not always a mistake.'
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

// Deny, and the archetype is the reason. Corp workloads reach the internet
// through the hub so that egress can be inspected centrally. A public IP on a
// network interface bypasses that path, which is why this is enforced here and
// absent from Online, where direct internet connectivity is the point.
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
// Brownfield: the same Deny, evaluated but not enforced
// ---------------------------------------------------------------------------

// The identical policy assigned to a duplicated Corp management group with
// enforcementMode DoNotEnforce. Subscriptions being adopted land here first.
// Compliance is measured against the real target policy with no risk to running
// workloads, and the subscription moves to Corp once its compliance is
// acceptable, at which point enforcement takes effect without the policy set
// changing at all.
//
// There is no additional cost. The hierarchy and the assignments are
// duplicated, the workloads are not. See ADR 0005.
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

// Left out of the deployment until bicep/20 creates the workspace in the
// management subscription. A DeployIfNotExists assignment with no target is not
// a partial configuration, it is a broken one: it would create an identity,
// grant it two roles across the hierarchy, and remediate nothing.
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
// Both of these configure every subscription under the intermediate root,
// including ones vended later, which is why they are policy rather than per
// subscription resources. DeployIfNotExists only acts when a subscription is
// created or updated, so existing subscriptions need a one off remediation
// task; the runbook covers it.

// Activity log to the central workspace. Activity log ingestion into Log
// Analytics is free, as are its first 90 days of retention.
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

// Service Health alerts. Emails whoever is listed when Azure has an incident,
// planned maintenance or an advisory affecting a subscription. The alert rule
// is free and so are the first 1,000 emails a month.
module deployServiceHealthAlerts '../modules/policy-assignment/main.bicep' = if (!empty(alertEmails)) {
  scope: managementGroup(prefix)
  name: 'assign-dine-service-health'
  params: {
    name: 'dine-service-health'
    displayName: 'Configure Service Health alerts in every subscription'
    policyDescription: 'Each subscription gets a Service Health alert rule and an action group, so an Azure incident affecting it reaches the platform team rather than being found in the portal afterwards.'
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
  DeployIfNotExists: empty(logAnalyticsWorkspaceId)
    ? 'not yet assigned, awaiting the workspace in bicep/20'
    : 'dine-nsg-diagnostics, at Platform Management'
}
