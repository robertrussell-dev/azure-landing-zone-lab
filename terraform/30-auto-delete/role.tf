# The janitor's role. Network Contributor would let a mistagged hub network be
# deleted, so this deletes only the six types the runbook lists. Keep the two in
# step. Assigned at the intermediate root because billable devices can be in any
# subscription. Not yet exercised by a real delete.
#
# The ID is fixed so the Bicep tree defines the same role.

data "azurerm_management_group" "intermediate_root" {
  name = var.prefix
}

resource "azurerm_role_definition" "janitor" {
  role_definition_id = "0c8d0f7e-026b-451b-a195-3f78e7c8ab4a"
  name               = "${var.prefix} auto delete janitor"
  description        = "Find resources through Resource Graph and delete billable network devices. Nothing else."
  scope              = data.azurerm_management_group.intermediate_root.id

  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/read",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Network/*/read",
      "Microsoft.Network/azureFirewalls/delete",
      "Microsoft.Network/virtualNetworkGateways/delete",
      "Microsoft.Network/bastionHosts/delete",
      "Microsoft.Network/virtualHubs/delete",
      "Microsoft.Network/virtualHubs/ipConfigurations/delete",
      "Microsoft.Network/firewallPolicies/delete",
      "Microsoft.Network/publicIPAddresses/delete",
    ]
  }

  assignable_scopes = [data.azurerm_management_group.intermediate_root.id]
}

# Entra replication wait, as in modules/policy-assignment.
resource "time_sleep" "identity_propagation" {
  depends_on      = [azurerm_automation_account.janitor]
  create_duration = "30s"
}

resource "azurerm_role_assignment" "janitor" {
  scope              = data.azurerm_management_group.intermediate_root.id
  role_definition_id = azurerm_role_definition.janitor.role_definition_resource_id
  principal_id       = azurerm_automation_account.janitor.identity[0].principal_id
  principal_type     = "ServicePrincipal"

  depends_on = [time_sleep.identity_propagation]
}
