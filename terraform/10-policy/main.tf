# Policy assignments.
#
# Deliberately a small set. Five assignments that can each be explained beat
# the full Azure landing zone default set, which is hundreds of policies nobody
# in this repo could defend individually.
#
# Scopes are resolved by data source lookup rather than by reading the state of
# terraform/00-management-groups. The management group names are deterministic,
# derived from the same prefix, so there is nothing to pass between root
# modules. That keeps each directory independently appliable and avoids needing
# a shared remote backend for a lab. The cost is that a wrong prefix fails at
# apply time rather than plan time.

data "azurerm_management_group" "intermediate_root" {
  name = var.prefix
}

data "azurerm_management_group" "corp" {
  name = "${var.prefix}-lz-corp"
}

data "azurerm_management_group" "corp_audit" {
  name = "${var.prefix}-lz-corp-audit"
}

data "azurerm_management_group" "platform_management" {
  name = "${var.prefix}-platform-management"
}

# Built in definition IDs, read from the platform rather than typed from
# memory. Effects and required roles were verified with
# "az policy definition show" before use, because a definition's allowed
# effects are not guessable. Notably the subnet NSG definition permits only
# AuditIfNotExists or Disabled, so it cannot be the Deny example that landing
# zone write ups often claim it is.
locals {
  definitions = {
    # AuditIfNotExists. Allowed effects: AuditIfNotExists, Disabled.
    subnets_need_nsg = "/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517"

    # Modify. Requires a managed identity holding Contributor.
    add_tag = "/providers/Microsoft.Authorization/policyDefinitions/4f9dc7db-30c1-420c-b61a-e1d640128d26"

    # Deny. No identity required.
    no_public_ip_on_nic = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114"

    # DeployIfNotExists. Requires an identity holding Log Analytics
    # Contributor and Monitoring Contributor.
    nsg_diagnostics = "/providers/Microsoft.Authorization/policyDefinitions/98a2e215-5382-489e-bd29-32e7190a39ba"
  }

  role_ids = {
    contributor               = "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
    log_analytics_contributor = "/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293"
    monitoring_contributor    = "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
  }
}

# ---------------------------------------------------------------------------
# Intermediate root: applies to everything
# ---------------------------------------------------------------------------

# Modify. Appends costCenter to resources that lack it.
#
# Security note worth stating rather than burying: this built in requires its
# managed identity to hold Contributor, not Tag Contributor. Assigning it here
# grants a policy created service principal Contributor across the whole
# hierarchy. Tag Contributor would be sufficient for what the policy actually
# does, but the required role list belongs to the definition and is not
# something the assignment can narrow. A custom definition asking only for Tag
# Contributor is the tighter option.
module "append_cost_center_tag" {
  source = "../modules/policy-assignment"

  name                 = "append-costcenter"
  display_name         = "Append costCenter tag to resources"
  description          = "Every resource in this lab carries costCenter so spend can be attributed and cleanup can find things. Applied at the intermediate root because it has no archetype specific behaviour."
  management_group_id  = data.azurerm_management_group.intermediate_root.id
  policy_definition_id = local.definitions.add_tag
  location             = var.location
  role_definition_ids  = [local.role_ids.contributor]

  parameters = {
    tagName  = "costCenter"
    tagValue = var.cost_center_tag_value
  }
}

# AuditIfNotExists at the top of the tree. Reports, never blocks.
module "audit_subnets_without_nsg" {
  source = "../modules/policy-assignment"

  name                 = "audit-subnet-nsg"
  display_name         = "Subnets should be associated with a network security group"
  description          = "Reported across the whole hierarchy so the platform team can see the shape of the estate. Audit rather than deny at this scope, because a subnet without a network security group is a finding to investigate, not always a mistake."
  management_group_id  = data.azurerm_management_group.intermediate_root.id
  policy_definition_id = local.definitions.subnets_need_nsg

  parameters = {
    effect = "AuditIfNotExists"
  }

  non_compliance_message = "This subnet has no network security group. Attach one, or record an exemption explaining why it does not need one."
}

# ---------------------------------------------------------------------------
# Corp archetype only: inheritance is scope dependent
# ---------------------------------------------------------------------------

# Deny, and the archetype is the reason. Corp workloads reach the internet
# through the hub so that egress can be inspected centrally. A public IP on a
# network interface bypasses that path, which is why this is enforced here and
# absent from Online, where direct internet connectivity is the point.
module "deny_public_ip_on_nic_corp" {
  source = "../modules/policy-assignment"

  name                 = "deny-nic-public-ip"
  display_name         = "Network interfaces must not have public IPs"
  description          = "Corp workloads route to the internet through the hub so egress can be inspected. A public IP on a network interface bypasses that path. Assigned at Corp only. Online does not carry this policy, because direct internet connectivity is what defines that archetype."
  management_group_id  = data.azurerm_management_group.corp.id
  policy_definition_id = local.definitions.no_public_ip_on_nic

  non_compliance_message = "Corp workloads cannot have public IPs on network interfaces. Route through the hub, or place this workload under the Online archetype instead."
}

# ---------------------------------------------------------------------------
# Brownfield: the same Deny, evaluated but not enforced
# ---------------------------------------------------------------------------

# The identical policy assigned to a duplicated Corp management group with
# enforcementMode DoNotEnforce. Subscriptions being adopted land here first.
# Compliance is measured against the real target policy with no risk to running
# workloads, and the subscription moves to Corp once its compliance is
# acceptable, at which point enforcement takes effect without the policy set
# changing at all.
#
# There is no additional cost. The hierarchy and the assignments are
# duplicated, the workloads are not. See ADR 0005.
module "deny_public_ip_on_nic_corp_audit" {
  source = "../modules/policy-assignment"

  name                 = "deny-nic-public-ip"
  display_name         = "Network interfaces must not have public IPs (audit only)"
  description          = "Same policy as Corp, assigned with enforcementMode DoNotEnforce. Subscriptions migrating in are measured against the target policy set without any deny taking effect. Moving the subscription to Corp is what turns enforcement on."
  management_group_id  = data.azurerm_management_group.corp_audit.id
  policy_definition_id = local.definitions.no_public_ip_on_nic

  enforce = false

  non_compliance_message = "This would be denied under the Corp archetype. Nothing is blocked here. Remediate before this subscription moves to Corp."
}

# ---------------------------------------------------------------------------
# DeployIfNotExists: only once there is a workspace to point at
# ---------------------------------------------------------------------------

# Left out of the plan until terraform/20 creates the workspace in the management
# subscription. A DeployIfNotExists assignment with no target is not a partial
# configuration, it is a broken one: it would create an identity, grant it two
# roles across the hierarchy, and remediate nothing.
module "deploy_nsg_diagnostics" {
  source = "../modules/policy-assignment"
  count  = var.log_analytics_workspace_id == null ? 0 : 1

  name                 = "dine-nsg-diagnostics"
  display_name         = "Deploy diagnostic settings for network security groups"
  description          = "Network security group logs are routed to the central workspace automatically, so that a workload team forgetting to configure diagnostics does not create a blind spot for the platform team."
  management_group_id  = data.azurerm_management_group.platform_management.id
  policy_definition_id = local.definitions.nsg_diagnostics
  location             = var.location

  role_definition_ids = [
    local.role_ids.log_analytics_contributor,
    local.role_ids.monitoring_contributor,
  ]

  parameters = {
    logAnalytics = var.log_analytics_workspace_id
  }
}
