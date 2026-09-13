variable "tenant_id" {
  description = "Entra ID tenant that owns the hierarchy."
  type        = string
}

variable "subscription_id" {
  description = "Subscription used only to initialize the provider. No resources are created in it."
  type        = string
}

variable "prefix" {
  description = "Same prefix used by terraform/00-management-groups. Management groups are looked up by the names it derives."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 2 to 10 lowercase alphanumeric characters, the same value as terraform/00-management-groups."
  }
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

variable "alert_emails" {
  description = "Addresses the Service Health alerts in every subscription notify. Empty leaves that assignment out."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Full resource ID of the workspace the DeployIfNotExists assignment targets. Null until terraform/20 creates it, which leaves the DeployIfNotExists assignment out of the plan. See README for why this is sequenced that way."
  type        = string
  default     = null
}
