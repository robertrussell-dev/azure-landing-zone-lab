variable "tenant_id" {
  description = "Entra ID tenant that owns the management group hierarchy."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "subscription_id" {
  description = "Subscription used only to initialise the provider. No resources are created in it by this configuration."
  type        = string
}

variable "prefix" {
  description = "Short lowercase prefix for management group names. Becomes part of every management group ID, which is immutable after creation."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 2 to 10 lowercase alphanumeric characters."
  }
}

variable "intermediate_root_display_name" {
  description = "Display name of the intermediate root management group. Unlike the name, this can be changed later."
  type        = string
}
