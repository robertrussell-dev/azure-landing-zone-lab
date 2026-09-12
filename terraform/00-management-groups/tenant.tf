# Tenant wide settings that sit on the tenant root group rather than in the
# tree. Both are free.

locals {
  tenant_root_group_id = "/providers/Microsoft.Management/managementGroups/${var.tenant_id}"
}

# ---------------------------------------------------------------------------
# Hierarchy settings
# ---------------------------------------------------------------------------
# Where a new subscription lands when nobody says otherwise, and who may create
# management groups.
#
# Sandboxes is the default because it is the least trusted placement: a
# subscription created outside vending starts somewhere with no route to on
# premises and no platform connectivity until someone decides where it belongs.
# Vended subscriptions are moved to their archetype straight away, so this only
# catches the ones that were not.
#
# Without requireAuthorizationForGroupCreation any user in the tenant can
# create management groups under the tenant root. With it, that needs write
# permission on the tenant root group.
#
# azapi because azurerm has no resource for these settings.
resource "azapi_resource" "hierarchy_settings" {
  type      = "Microsoft.Management/managementGroups/settings@2023-04-01"
  name      = "default"
  parent_id = local.tenant_root_group_id

  body = {
    properties = {
      # The name, not the resource ID. The API accepts either but stores and
      # returns the name, so an ID here reads as a change on every plan.
      defaultManagementGroup               = azurerm_management_group.sandboxes.name
      requireAuthorizationForGroupCreation = true
    }
  }
}

# ---------------------------------------------------------------------------
# A least privilege role for the hierarchy
# ---------------------------------------------------------------------------
# This lab runs with Owner at the root scope "/", and "/" accepts built in roles
# only, so the narrowest grant there is Contributor over the whole tenant. The
# tenant root group is an ordinary scope that accepts custom roles, so the
# narrow alternative can be a real role rather than a paragraph: enough to
# create, move and delete management groups and write the deployment records
# that go with them, and nothing else. It covers the groups, which is the part
# that changes over time. The hierarchy settings and the role itself are one off
# setup, and need broader access than the role grants.
#
# Defined, not assigned. The action list covers what this directory creates; it
# has not been exercised through an assignment. The role definition ID is fixed
# so that the Bicep tree describes the same role rather than a second copy.
resource "azurerm_role_definition" "hierarchy_deployer" {
  role_definition_id = "9eeae106-cb05-4621-8e59-1f2bea524ec3"
  name               = "${var.prefix} hierarchy deployer"
  description        = "Create, move and delete management groups under the tenant root group, and run the deployments that do it. Nothing else."
  scope              = local.tenant_root_group_id

  permissions {
    actions = [
      "Microsoft.Management/managementGroups/read",
      "Microsoft.Management/managementGroups/write",
      "Microsoft.Management/managementGroups/delete",
      "Microsoft.Resources/deployments/*",
    ]
  }

  assignable_scopes = [local.tenant_root_group_id]
}
