variable "name" {
  description = "Budget name. Immutable once created."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,63}$", var.name))
    error_message = "Budget names allow letters, digits, hyphens and underscores, up to 63 characters."
  }
}

variable "subscription_id" {
  description = "GUID of the subscription the budget applies to. Pass the bare GUID, not a resource ID. The module builds the scope."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a bare GUID, for example 00000000-0000-0000-0000-000000000000."
  }
}

variable "amount" {
  description = "Budget amount in the billing account currency."
  type        = number

  validation {
    condition     = var.amount > 0
    error_message = "A budget amount must be greater than zero."
  }
}

variable "contact_emails" {
  description = "Addresses notified when a threshold is crossed. At least one, or the budget notifies nobody and is decoration."
  type        = list(string)

  validation {
    condition     = length(var.contact_emails) > 0
    error_message = "A budget with no contacts cannot alert anyone. Provide at least one address."
  }
}

variable "actual_threshold_percent" {
  description = "Percentage of the budget at which an alert fires on actual spend. Tells you what has already been spent."
  type        = number
  default     = 80

  validation {
    condition     = var.actual_threshold_percent > 0 && var.actual_threshold_percent <= 1000
    error_message = "Threshold must be between 1 and 1000 percent."
  }
}

variable "forecast_threshold_percent" {
  description = "Percentage at which an alert fires on forecast spend. This is the threshold that leaves time to act, because it fires before the money is gone."
  type        = number
  default     = 100

  validation {
    condition     = var.forecast_threshold_percent > 0 && var.forecast_threshold_percent <= 1000
    error_message = "Threshold must be between 1 and 1000 percent."
  }
}

variable "time_grain" {
  description = "Budget reset period."
  type        = string
  default     = "Monthly"

  validation {
    condition     = contains(["Monthly", "Quarterly", "Annually"], var.time_grain)
    error_message = "time_grain must be Monthly, Quarterly or Annually."
  }
}
