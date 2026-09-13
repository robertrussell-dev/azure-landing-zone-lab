# Policy assignments. Eight, each one explainable: six show one effect each and
# two are the subscription baseline.
#
# Scopes are looked up by name from the prefix instead of read from another
# root's state. A wrong prefix fails at apply, not plan.

data "azurerm_management_group" "intermediate_root" {
  name = var.prefix
}

data "azurerm_management_group" "corp" {
  name = "${var.prefix}-lz-corp"
}

data "azurerm_management_group" "corp_audit" {
  name = "${var.prefix}-lz-corp-audit"
}

data "azurerm_management_group" "platform" {
  name = "${var.prefix}-platform"
}

data "azurerm_management_group" "platform_management" {
  name = "${var.prefix}-platform-management"
}

# Built in definitions. Effects and required roles checked with
# "az policy definition show".
locals {
  definitions = {
    # AuditIfNotExists. Allowed effects: AuditIfNotExists, Disabled. It reads a
    # Defender for Cloud assessment rather than the subnet, so it only reports
    # correctly where Defender is on; modules/subscription-baseline turns it on.
    subnets_need_nsg = "/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517"

    # Modify. Requires a managed identity holding Contributor.
    add_tag = "/providers/Microsoft.Authorization/policyDefinitions/4f9dc7db-30c1-420c-b61a-e1d640128d26"

    # Deny. No identity required.
    no_public_ip_on_nic = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114"

    # DeployIfNotExists. Requires an identity holding Log Analytics
    # Contributor and Monitoring Contributor.
    nsg_diagnostics = "/providers/Microsoft.Authorization/policyDefinitions/98a2e215-5382-489e-bd29-32e7190a39ba"

    # DeployIfNotExists. Same two roles as nsg_diagnostics.
    activity_log = "/providers/Microsoft.Authorization/policyDefinitions/2465583e-4e78-4c15-b6be-a36cbc7c8b0f"

    # DeployIfNotExists. Requires Monitoring Policy Contributor. Creates a
    # resource group, an action group and an alert rule in each subscription.
    service_health = "/providers/Microsoft.Authorization/policyDefinitions/98903777-a9f6-47f5-90a9-acaf62ab01a8"

    # DenyAction. No identity required.
    no_delete = "/providers/Microsoft.Authorization/policyDefinitions/78460a36-508a-49a4-b2b2-2f5ec564f4bb"
  }

  role_ids = {
    contributor               = "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
    log_analytics_contributor = "/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293"
    monitoring_contributor    = "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
    monitoring_policy_contrib = "/providers/Microsoft.Authorization/roleDefinitions/47be4a87-7950-4631-9daf-b664a405f074"
  }
}

# ---------------------------------------------------------------------------
# Intermediate root: applies to everything
# ---------------------------------------------------------------------------

# Modify. Appends costCenter to resources that lack it.
#
# The built in requires Contributor, not Tag Contributor, so its identity gets
# Contributor across the hierarchy. A custom definition could ask for less.
module "append_cost_center_tag" {
  source = "../modules/policy-assignment"

  name                 = "append-costcenter"
  display_name         = "Append costCenter tag to resources"
  description          = "Every resource in this lab carries costCenter so spend can be attributed and cleanup can find things. Applied at the intermediate root because it has no archetype specific behavior."
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

# Deny at Corp only. Online is meant to have direct internet access.
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
# Platform only: things that must not be deleted
# ---------------------------------------------------------------------------

# At Platform, so a future platform workspace is covered too. It doesn't stop a
# resource group delete; the lock in terraform/20 does. Destroying terraform/20
# needs this removed first. ADR 0008 has the reasoning.
module "deny_platform_workspace_delete" {
  source = "../modules/policy-assignment"

  name                 = "deny-platform-delete"
  display_name         = "Platform Log Analytics workspaces cannot be deleted"
  description          = "Every activity log and diagnostic setting in the hierarchy sends to the platform workspace, so deleting it silently breaks log collection everywhere. Assigned at Platform so a workspace added to any platform subscription is covered. Bypassed only by an exemption, which needs rights on this assignment, not just on the subscription."
  management_group_id  = data.azurerm_management_group.platform.id
  policy_definition_id = local.definitions.no_delete

  parameters = {
    effect                                   = "DenyAction"
    listOfResourceTypesDisallowedForDeletion = ["Microsoft.OperationalInsights/workspaces"]
  }

  non_compliance_message = "Platform workspaces cannot be deleted. If this really has to go, ask the platform team for a policy exemption with an expiry."
}

# ---------------------------------------------------------------------------
# Brownfield: the same Deny, evaluated but not enforced
# ---------------------------------------------------------------------------

# The Corp Deny with enforcement off. See ADR 0005.
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

# Skipped until terraform/20 creates the workspace. Without a target it would
# create an identity with two roles and remediate nothing.
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

# ---------------------------------------------------------------------------
# Intermediate root: the subscription baseline
# ---------------------------------------------------------------------------
# Policy, so subscriptions vended later get them too. Existing subscriptions
# need a one off remediation task; the runbook covers it.

# Activity log ingestion into Log Analytics is free.
module "deploy_activity_log" {
  source = "../modules/policy-assignment"
  count  = var.log_analytics_workspace_id == null ? 0 : 1

  name                 = "dine-activity-log"
  display_name         = "Send subscription activity logs to the central workspace"
  description          = "Every subscription streams its activity log to the platform workspace, so there is one place to answer who changed what, including in subscriptions vended after this was assigned."
  management_group_id  = data.azurerm_management_group.intermediate_root.id
  policy_definition_id = local.definitions.activity_log
  location             = var.location

  role_definition_ids = [
    local.role_ids.log_analytics_contributor,
    local.role_ids.monitoring_contributor,
  ]

  parameters = {
    logAnalytics = var.log_analytics_workspace_id
  }
}

# Free: the alert rule, and the first 1,000 emails a month.
module "deploy_service_health_alerts" {
  source = "../modules/policy-assignment"
  count  = length(var.alert_emails) == 0 ? 0 : 1

  name                 = "dine-service-health"
  display_name         = "Configure Service Health alerts in every subscription"
  description          = "Each subscription gets a Service Health alert rule and an action group, so an Azure incident affecting it reaches the platform team rather than being found in the portal afterward."
  management_group_id  = data.azurerm_management_group.intermediate_root.id
  policy_definition_id = local.definitions.service_health
  location             = var.location

  role_definition_ids = [local.role_ids.monitoring_policy_contrib]

  parameters = {
    resourceGroupName     = "rg-service-health-alerts"
    resourceGroupLocation = var.location
    actionGroupResources = {
      actionGroupEmail    = var.alert_emails
      eventHubResourceId  = []
      functionResourceId  = ""
      functionTriggerUrl  = ""
      logicappCallbackUrl = ""
      logicappResourceId  = ""
      webhookServiceUri   = []
    }
  }
}
