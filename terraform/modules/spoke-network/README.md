# spoke-network

One spoke virtual network: subnets derived from the spoke's own prefix, a
baseline network security group, a route table, and both halves of the peering
with the hub.

![Hub and spoke network](../../../docs/diagrams/hub-spoke-network.svg)

Everything this module creates is free to leave running, which is why ADR 0004
chose hub and spoke for this lab. The things that bill are in
[`terraform/90-optional-network/billable.tf`](../../90-optional-network/billable.tf),
behind flags.

## Why this is a module

One caller, which breaks the rule in [modules/README.md](../README.md); that
README explains why.

## Usage

```hcl
module "spoke" {
  source   = "../modules/spoke-network"
  for_each = var.spokes

  providers = {
    azurerm = azurerm.connectivity
  }

  name                = each.key
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  address_space       = each.value.address_space
  archetype           = each.value.archetype

  hub_virtual_network_id   = azurerm_virtual_network.hub.id
  hub_virtual_network_name = azurerm_virtual_network.hub.name
  hub_resource_group_name  = azurerm_resource_group.hub.name

  firewall_private_ip = var.deploy_firewall ? azurerm_firewall.hub[0].ip_configuration[0].private_ip_address : ""
  use_remote_gateways = each.value.archetype == "corp" && var.deploy_vpn_gateway
  peer_prefixes       = ["10.2.0.0/16"]
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | Short spoke name. Used in every resource name. |
| `resource_group_name` | string | required | Where the spoke's network lives. |
| `location` | string | required | Region. |
| `address_space` | string | required | The spoke's whole prefix. A /22, or larger. Subnets are derived from it. |
| `archetype` | string | required | `corp` or `online`. Decides routing and gateway transit. |
| `hub_virtual_network_id` | string | required | Hub virtual network to peer with. |
| `hub_virtual_network_name` | string | required | Needed to create the hub side of the peering. |
| `hub_resource_group_name` | string | required | Resource group holding the hub. |
| `firewall_private_ip` | string | `""` | Empty leaves the route table in place and unpopulated. |
| `use_remote_gateways` | bool | `false` | Azure rejects the peering if this is true and the hub has no gateway. |
| `peer_prefixes` | list(string) | `[]` | Other archetypes' supernets, routed to the firewall. |
| `subnet_nsg_policy_assignment_id` | string | `""` | The subnet NSG audit assignment. When set, `snet-appgw` gets a Waiver against it. |
| `appgw_waiver_expires_on` | string | `2027-09-12T00:00:00Z` | When that waiver lapses. |
| `tags` | map(string) | `{}` | |

## Outputs

| Name | Description |
|---|---|
| `virtual_network_id` | Resource ID of the spoke. |
| `virtual_network_name` | Name of the spoke. |
| `address_space` | The prefix, echoed back so callers can build routes without recomputing it. |
| `subnet_ids` | Subnet IDs by short name. |
| `subnet_prefixes` | The derived prefixes, so the plan can be checked without reading state. |

## Notes

**Subnets are derived, not listed.** `cidrsubnet` splits the /22 into three
/24s and a /26, matching [docs/ip-plan.md](../../../docs/ip-plan.md), so no
subnet can fall outside the spoke's allocation. The Bicep module's `cidrSubnet`
gives the same prefixes.

**The archetype is enforced by peering.** `corp` gets a default route to the
firewall and `use_remote_gateways`, so it reaches on premises through the hub.
`online` gets neither, so it can't.

**`use_remote_gateways` is gated on a gateway actually existing.** Azure rejects
the peering outright if the flag is true and the hub has no gateway, so the
caller ties it to the gateway flags rather than to the archetype alone.

**Routes are only written when there's a firewall.** An empty
`firewall_private_ip` gives an empty route table instead of routes to nowhere.
The table always exists, so enabling the firewall only adds routes.

**The Application Gateway subnet is left bare**, with no network security group
or route table. Application Gateway v2 needs inbound 65200-65535 from
`GatewayManager`, and a default route to a firewall breaks its control plane.
When the caller passes `subnet_nsg_policy_assignment_id`, the subnet gets a
Waiver against the subnet audit, expiring on `appgw_waiver_expires_on`.
