variable "tenant_id" {
  description = "Entra ID tenant that owns the hierarchy."
  type        = string
}

variable "subscription_id" {
  description = "Subscription used only to initialize the default provider. Nothing is created in it."
  type        = string
}

variable "management_subscription_id" {
  description = "GUID of the management subscription. The Automation account is created there."
  type        = string
}

variable "prefix" {
  description = "Same prefix used by terraform/00-management-groups. The janitor searches and acts under the intermediate root of that name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 2 to 10 lowercase alphanumeric characters, the same value as terraform/00-management-groups."
  }
}

variable "location" {
  description = "Region for the Automation account."
  type        = string
  default     = "westus2"
}

variable "run_interval_hours" {
  description = "Hours between runs. Each run takes well under a minute, and Automation includes 500 job minutes a month free. Every 2 hours is at most 372 runs a month, inside the allowance even if each is billed as a full minute. Every hour would not be."
  type        = number
  default     = 2

  validation {
    condition     = var.run_interval_hours >= 2 && var.run_interval_hours <= 24
    error_message = "run_interval_hours must be between 2 and 24. Hourly runs exceed the free job minutes."
  }
}
