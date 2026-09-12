variable "subscription_id" {
  description = "GUID of the subscription to baseline."
  type        = string
}

variable "security_contact_emails" {
  description = "Addresses Defender for Cloud notifies about high severity alerts. Empty skips the contact."
  type        = list(string)
  default     = []
}

variable "resource_providers" {
  description = "Resource providers to register. The defaults are the ones the platform baseline itself uses: Defender for Cloud, policy compliance, and the activity log and alert resources the policy assignments deploy."
  type        = list(string)
  default = [
    "Microsoft.Security",
    "Microsoft.PolicyInsights",
    "Microsoft.Insights",
  ]
}
