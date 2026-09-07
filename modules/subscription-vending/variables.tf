variable "display_name" {
  description = "Subscription display name. Also the default alias and the budget name suffix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,60}$", var.display_name))
    error_message = "Use lowercase letters, digits and hyphens, 3 to 60 characters, so the name is safe to reuse in resource names."
  }
}

variable "alias" {
  description = "Alias object name. Defaults to display_name. Immutable, and reusing an existing alias adopts that subscription rather than creating a new one."
  type        = string
  default     = null
}

variable "billing_scope_id" {
  description = "Invoice section, billing profile or billing account resource ID the subscription is billed to. Permissions here are a separate model from Azure RBAC: management group Owner grants nothing at billing scope."
  type        = string

  validation {
    condition     = startswith(var.billing_scope_id, "/providers/Microsoft.Billing/billingAccounts/")
    error_message = "billing_scope_id must be a billing scope resource ID starting with /providers/Microsoft.Billing/billingAccounts/."
  }
}

variable "management_group_id" {
  description = "Full resource ID of the management group to place the subscription under. This determines the inherited policy and role assignments, so it is the archetype decision from ADR 0003 made concrete."
  type        = string

  validation {
    condition     = startswith(var.management_group_id, "/providers/Microsoft.Management/managementGroups/")
    error_message = "management_group_id must be a full management group resource ID."
  }
}

variable "workload" {
  description = "Production or DevTest. DevTest attracts lower rates and requires an eligible billing plan. Immutable after creation."
  type        = string
  default     = "Production"

  validation {
    condition     = contains(["Production", "DevTest"], var.workload)
    error_message = "workload must be Production or DevTest."
  }
}

variable "tags" {
  description = "Tags applied to the subscription. Note that a Modify policy may add more, and Terraform will plan to remove them unless the caller ignores those keys."
  type        = map(string)
  default     = {}
}

variable "budget_amount" {
  description = "Monthly budget in the billing account currency. Every vended subscription gets one."
  type        = number
  default     = 50

  validation {
    condition     = var.budget_amount > 0
    error_message = "A budget amount must be greater than zero."
  }
}

variable "budget_contact_emails" {
  description = "Who is alerted when the budget threshold is crossed. Should be the workload team's on call contact, not the platform team."
  type        = list(string)

  validation {
    condition     = length(var.budget_contact_emails) > 0
    error_message = "A budget with no contacts cannot alert anyone. Provide at least one address."
  }
}

variable "budget_actual_threshold_percent" {
  description = "Alert threshold on actual spend, as a percentage of the budget."
  type        = number
  default     = 80
}

variable "budget_forecast_threshold_percent" {
  description = "Alert threshold on forecast spend, as a percentage of the budget. This is the one that leaves time to act."
  type        = number
  default     = 100
}
