output "brownfield_placement" {
  description = "Where the adopted subscription now sits, and what that means for enforcement."
  value = {
    subscription_id  = var.brownfield_subscription_id
    management_group = data.azurerm_management_group.corp_audit.name
    enforcement      = "DoNotEnforce, policies evaluated but not acted on"
    to_enforce       = "move this association to ${var.prefix}-lz-corp"
  }
}
