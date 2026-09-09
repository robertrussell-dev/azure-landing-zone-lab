variable "tenant_id" {
  description = "Entra ID tenant that owns the hierarchy."
  type        = string
}

variable "subscription_id" {
  description = "Subscription used only to initialise the provider."
  type        = string
}

variable "prefix" {
  description = "Same prefix used by infra/00-management-groups."
  type        = string
}

variable "brownfield_subscription_id" {
  description = "GUID of the pre existing subscription adopted into the hierarchy under the audit only Corp archetype."
  type        = string
}

variable "brownfield_subscription_name" {
  description = "Short name used in the budget resource name. Not the subscription display name."
  type        = string
  default     = "demo"
}

variable "monthly_budget_amount" {
  description = "Monthly budget in the billing account currency. A budget notifies, it does not cap spending."
  type        = number
  default     = 20
}

variable "budget_alert_emails" {
  description = "Addresses notified when a budget threshold is crossed. Kept in tfvars because it is personal data."
  type        = list(string)
}

variable "create_subscriptions" {
  description = "Whether to vend subscriptions. Creation is a billing account operation, so it is behind a flag rather than implied by an apply."
  type        = bool
  default     = false
}

variable "billing_scope_id" {
  description = "Invoice section resource ID subscriptions are billed to. Format: /providers/Microsoft.Billing/billingAccounts/{ba}/billingProfiles/{bp}/invoiceSections/{is}. Null when create_management_subscription is false."
  type        = string
  default     = null
}

variable "management_subscription_id" {
  description = "GUID of the management subscription. Set after it is created, so that resources inside it target the right subscription."
  type        = string
  default     = null
}

variable "location" {
  description = "Region for resources created inside the management subscription."
  type        = string
  default     = "westus2"
}
