variable "tenant_id" {
  description = "Entra ID tenant."
  type        = string
}

variable "subscription_id" {
  description = "Subscription used only to initialize the default provider. Nothing is created in it."
  type        = string
}

variable "connectivity_subscription_id" {
  description = "GUID of the connectivity subscription. Everything in this directory is created there."
  type        = string
}

variable "prefix" {
  description = "Management group prefix used by terraform/00-management-groups. The exemptions name the subnet network security group assignment at the intermediate root, whose ID is built from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 2 to 10 lowercase alphanumeric characters, the same value as terraform/00-management-groups."
  }
}

variable "location" {
  description = "Region for the hub and the spokes."
  type        = string
  default     = "westus2"
}

variable "hub_address_space" {
  description = "The hub's prefix. A /20 out of the platform /16, per docs/ip-plan. Subnet layout is derived from it."
  type        = string
  default     = "10.0.0.0/20"
}

variable "spokes" {
  description = "The spokes to build. One /22 per workload per environment, allocated sequentially. archetype decides routing and gateway transit."
  type = map(object({
    address_space = string
    archetype     = string
  }))
  default = {
    corp-payments-prod = {
      address_space = "10.1.0.0/22"
      archetype     = "corp"
    }
    online-portal-prod = {
      address_space = "10.2.0.0/22"
      archetype     = "online"
    }
  }
}

variable "archetype_supernets" {
  description = "The whole prefix belonging to each archetype. Routes target these blocks instead of individual spokes, which is why Corp and Online have separate address blocks. One route covers 64 spokes."
  type        = map(string)
  default = {
    corp   = "10.1.0.0/16"
    online = "10.2.0.0/16"
  }
}

# ---------------------------------------------------------------------------
# The flags. Everything above this line is free to leave running.
# ---------------------------------------------------------------------------
# Retail prices, West US 2, USD, from the retail prices API on 2026-09-12.
# Each of these bills by the hour whether or not traffic crosses it.

variable "deploy_firewall" {
  description = "Azure Firewall in the hub. Standard SKU: 1.25 per hour, about 912 per month, plus 0.016 per GB processed. The single most expensive thing in this repository. Nothing routes through the hub without it, so the spoke route tables stay empty while this is false."
  type        = bool
  default     = false
}

variable "firewall_sku_tier" {
  description = "Basic, Standard or Premium. Basic is 0.395 per hour, about 288 per month, and is enough to demonstrate the topology."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Basic, Standard or Premium."
  }
}

variable "deploy_vpn_gateway" {
  description = "VPN gateway in the hub. VpnGw1: 0.19 per hour, about 139 per month. Deploying one takes 30 to 45 minutes and destroying it takes about as long, which matters more than the money when you are trying to take it down the same day."
  type        = bool
  default     = false
}

variable "deploy_expressroute_gateway" {
  description = "ExpressRoute gateway in the hub. Standard: 0.19 per hour, about 139 per month, and that is only the gateway. The circuit itself is a separate carrier contract and is not created here."
  type        = bool
  default     = false
}

variable "deploy_bastion" {
  description = "Azure Bastion in the hub. Standard: 0.29 per hour, about 212 per month. Basic is 0.19 per hour, about 139."
  type        = bool
  default     = false
}

variable "deploy_route_server" {
  description = "Azure Route Server in the hub. About 0.10 per hour per routing unit, roughly 73 per month at minimum capacity. Only useful if you run a BGP speaking network virtual appliance, and there is not one here."
  type        = bool
  default     = false
}

variable "billable_ttl_hours" {
  description = "How long a billable device may exist before terraform/30-auto-delete deletes it. Stamped on each device as its deleteAfter tag when it is created. The default is a working day; the most expensive device here costs about 10 over that window."
  type        = number
  default     = 8

  validation {
    condition     = var.billable_ttl_hours >= 1 && var.billable_ttl_hours <= 72
    error_message = "billable_ttl_hours must be between 1 and 72."
  }
}

variable "budget_alert_emails" {
  description = "Who gets told if this subscription's spend crosses a threshold. A budget does not cap anything, but leaving a gateway running is exactly the mistake it exists to catch."
  type        = list(string)
  default     = []
}

variable "monthly_budget_amount" {
  description = "Monthly budget for the connectivity subscription, in the billing account currency."
  type        = number
  default     = 50
}
