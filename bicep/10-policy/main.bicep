// Policy assignments.
//
// Deliberately a small set. Five assignments that can each be explained beat
// the full Azure landing zone default set, which is hundreds of policies nobody
// in this repo could defend individually.
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
  // AuditIfNotExists. Allowed effects: AuditIfNotExists, Disabled.
  subnetsNeedNsg: tenantResourceId('Microsoft.Authorization/policyDefinitions', 'e71308d3-144b-4262-b144-efdc3cc90517')

  // Modify. Requires a managed identity holding Contributor.
  addTag: tenantResourceId('Microsoft.Authorization/policyDefinitions', '4f9dc7db-30c1-420c-b61a-e1d640128d26')

  // Deny. No identity required.
  noPublicIpOnNic: tenantResourceId('Microsoft.Authorization/policyDefinitions', '83a86a26-fd1f-447c-b59d-e51f44264114')

  // DeployIfNotExists. Requires an identity holding Log Analytics Contributor
  // and Monitoring Contributor.
  nsgDiagnostics: tenantResourceId('Microsoft.Authorization/policyDefinitions', '98a2e215-5382-489e-bd29-32e7190a39ba')
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
