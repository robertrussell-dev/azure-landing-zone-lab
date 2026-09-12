output "assignment_ids" {
  description = "Policy assignment IDs by short name."
  value = merge(
    {
      append_cost_center_tag           = module.append_cost_center_tag.id
      audit_subnets_without_nsg        = module.audit_subnets_without_nsg.id
      deny_public_ip_on_nic_corp       = module.deny_public_ip_on_nic_corp.id
      deny_public_ip_on_nic_corp_audit = module.deny_public_ip_on_nic_corp_audit.id
    },
    length(module.deploy_nsg_diagnostics) > 0 ? {
      deploy_nsg_diagnostics = module.deploy_nsg_diagnostics[0].id
    } : {},
  )
}

output "effects_demonstrated" {
  description = "Which policy effect each assignment exercises, for the README."
  value = {
    Modify            = "append-costcenter, at the intermediate root"
    AuditIfNotExists  = "audit-subnet-nsg, at the intermediate root"
    Deny              = "deny-nic-public-ip, at Corp"
    DoNotEnforce      = "deny-nic-public-ip, at Corp (audit only), same definition, enforcement off"
    DeployIfNotExists = var.log_analytics_workspace_id == null ? "not yet assigned, awaiting the workspace in terraform/20" : "dine-nsg-diagnostics, at Platform Management"
  }
}
