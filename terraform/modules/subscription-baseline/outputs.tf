output "registered_providers" {
  description = "Resource providers this module registered."
  value       = sort(keys(azapi_resource_action.register))
}

output "cspm_tier" {
  description = "The Defender for Cloud posture tier this module set. Free is Foundational CSPM."
  value       = azapi_update_resource.foundational_cspm.body.properties.pricingTier
}
