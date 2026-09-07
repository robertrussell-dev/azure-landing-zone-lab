variable "tenant_id" {
  description = "Entra ID tenant that owns the hierarchy."
  type        = string
}

variable "subscription_id" {
  description = "Subscription used only to initialise the provider. No resources are created in it."
  type        = string
}

variable "prefix" {
  description = "Same prefix used by infra/00-management-groups. Management groups are looked up by the names it derives."
  type        = string
}

variable "location" {
  description = "Region for the managed identities created by Modify and DeployIfNotExists assignments. The identity's location does not constrain where policy applies."
  type        = string
  default     = "westus2"
}

variable "cost_center_tag_value" {
  description = "Value the Modify assignment appends as costCenter."
  type        = string
  default     = "lab"
}

variable "log_analytics_workspace_id" {
  description = "Full resource ID of the workspace the DeployIfNotExists assignment targets. Null until infra/20 creates it, which leaves the DeployIfNotExists assignment out of the plan. See README for why this is sequenced that way."
  type        = string
  default     = null
}
