variable "tenant_id" {
  description = "Entra ID tenant."
  type        = string
}

variable "subscription_id" {
  description = "Subscription used only to initialise the default provider. Nothing is created in it."
  type        = string
}

variable "brownfield_subscription_id" {
  description = "The adopted subscription that these deliberately non compliant resources are created in."
  type        = string
}

variable "location" {
  description = "Region for the seeded resources."
  type        = string
  default     = "westus2"
}
