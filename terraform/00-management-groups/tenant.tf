# Tenant wide settings that sit on the tenant root group rather than in the
# tree. Both are free.

locals {
  tenant_root_group_id = "/providers/Microsoft.Management/managementGroups/${var.tenant_id}"
}

# ---------------------------------------------------------------------------
# Hierarchy settings
# ---------------------------------------------------------------------------
# New subscriptions land in Sandboxes, the least trusted placement, until
# someone places them. Vending places its own, so this only catches the rest.
# Creating management groups needs write access on the tenant root group; by
# default any user can.
#
# azapi because azurerm has no resource for these settings.
resource "azapi_resource" "hierarchy_settings" {
  type      = "Microsoft.Management/managementGroups/settings@2023-04-01"
  name      = "default"
  parent_id = local.tenant_root_group_id

  body = {
    properties = {
      # The name, not the ID. The API stores the name, so an ID shows as a
      # change on every plan.
      defaultManagementGroup               = azurerm_management_group.sandboxes.name
      requireAuthorizationForGroupCreation = true
    }
  }
}

# ---------------------------------------------------------------------------
# A least privilege role for the hierarchy
# ---------------------------------------------------------------------------
# "/" only takes built in roles, so the narrowest grant there is Contributor
# over the tenant. The tenant root group takes custom roles, so this one can
# manage the groups and nothing else. It doesn't cover the settings above or
# itself. Defined, not assigned or tested. The ID is fixed so the Bicep tree
# defines the same role.
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
