variable "tenant_id" {
  description = "Entra ID tenant."
  type        = string
}

variable "subscription_id" {
  description = "Subscription used only to initialize the default provider. Nothing is created in it."
  type        = string
}

variable "brownfield_subscription_id" {
  description = "The adopted subscription the noncompliant seed resources go in."
  type        = string
}

variable "location" {
  description = "Region for the seeded resources."
  type        = string
  default     = "westus2"
}
