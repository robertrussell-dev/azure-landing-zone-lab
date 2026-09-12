variable "name" {
  description = "Short spoke name, for example corp-payments-prod. Used in every resource name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the spoke's network lives in."
  type        = string
}

variable "location" {
  description = "Region for the spoke."
  type        = string
}

variable "address_space" {
  description = "The spoke's whole prefix. One /22 per workload per environment is the standard allocation in docs/ip-plan. Subnets are derived from it rather than listed, so a spoke cannot be given a subnet that falls outside its own allocation."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && tonumber(split("/", var.address_space)[1]) <= 22
    error_message = "address_space must be valid CIDR and no smaller than a /22, or the derived subnets will not fit."
  }
}

variable "archetype" {
  description = "corp or online. This is not a label. corp gets a default route to the firewall and gateway transit to on premises, online gets neither, and that is what actually enforces the archetype. See ADR 0003."
  type        = string

  validation {
    condition     = contains(["corp", "online"], var.archetype)
    error_message = "archetype must be corp or online."
  }
}

variable "hub_virtual_network_id" {
  description = "Resource ID of the hub virtual network to peer with."
  type        = string
}

variable "hub_virtual_network_name" {
  description = "Name of the hub virtual network. Needed to create the hub side of the peering."
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group holding the hub virtual network."
  type        = string
}

variable "firewall_private_ip" {
  description = "Private IP of the hub firewall. Empty when no firewall is deployed, which leaves the route table in place but empty. A route to a next hop that does not exist is a black hole, so the routes are only written when there is something to point at."
  type        = string
  default     = ""
}

variable "use_remote_gateways" {
  description = "Whether this spoke routes to on premises through the hub's gateway. Azure rejects the peering if this is true and the hub has no gateway, so the caller ties it to whether a gateway was actually deployed."
  type        = bool
  default     = false
}

variable "peer_prefixes" {
  description = "Prefixes belonging to other archetypes, routed to the firewall so that spoke to spoke traffic is inspected. Peering is not transitive, so without these a corp spoke and an online spoke cannot reach each other at all."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource in the spoke."
  type        = map(string)
  default     = {}
}
