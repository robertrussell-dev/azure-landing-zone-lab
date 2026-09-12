variable "name" {
  description = "Assignment name. Becomes part of the resource ID, so it is immutable. Azure limits this to 24 characters at management group scope."
  type        = string

  validation {
    condition     = length(var.name) <= 24
    error_message = "Policy assignment names are limited to 24 characters at management group scope."
  }
}

variable "display_name" {
  description = "Human readable name shown in the portal compliance view."
  type        = string
}

variable "description" {
  description = "Why this policy is assigned here. Shown to anyone who hits it, so write it for them."
  type        = string
}

variable "management_group_id" {
  description = "Full resource ID of the management group to assign at."
  type        = string
}

variable "policy_definition_id" {
  description = "Full resource ID of the policy definition or initiative."
  type        = string
}

variable "parameters" {
  description = "Policy parameters as a flat map. The module wraps each value in the {\"value\": x} shape Azure expects."
  type        = map(any)
  default     = {}
}

variable "enforce" {
  description = "true assigns with enforcementMode Default. false assigns with DoNotEnforce, which evaluates compliance and reports it but does not act on the effect. false is the brownfield audit only pattern."
  type        = bool
  default     = true
}

variable "role_definition_ids" {
  description = "Role definition IDs the assignment's managed identity needs. Required for Modify and DeployIfNotExists effects, empty for Audit and Deny. Read these off the definition's policyRule.then.details.roleDefinitionIds rather than guessing."
  type        = list(string)
  default     = []
}

variable "location" {
  description = "Region for the system assigned managed identity. Required whenever role_definition_ids is non empty, ignored otherwise."
  type        = string
  default     = null
}

variable "non_compliance_message" {
  description = "Message shown when a resource fails this policy. Null falls back to Azure's generic text, which tells the reader nothing."
  type        = string
  default     = null
}
