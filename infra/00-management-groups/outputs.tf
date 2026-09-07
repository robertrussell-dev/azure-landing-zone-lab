# Consumed by infra/10-policy and infra/20-subscription-placement so that
# scope IDs are never hardcoded as strings in more than one place.

output "intermediate_root_id" {
  description = "Resource ID of the intermediate root management group."
  value       = azurerm_management_group.intermediate_root.id
}

output "management_group_ids" {
  description = "Every management group in the hierarchy, keyed by short name."
  value = merge(
    {
      intermediate_root = azurerm_management_group.intermediate_root.id
      platform          = azurerm_management_group.platform.id
      landingzones      = azurerm_management_group.landing_zones.id
      sandboxes         = azurerm_management_group.sandboxes.id
      decommissioned    = azurerm_management_group.decommissioned.id
    },
    { for k, v in azurerm_management_group.platform_child : "platform-${k}" => v.id },
    { for k, v in azurerm_management_group.landing_zone_archetype : "lz-${k}" => v.id },
  )
}
