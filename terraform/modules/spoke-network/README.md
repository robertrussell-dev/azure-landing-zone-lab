# spoke-network

One spoke virtual network: subnets derived from the spoke's own prefix, a
baseline network security group, a route table, and both halves of the peering
with the hub.

![Hub and spoke network](../../../docs/diagrams/hub-spoke-network.svg)

Everything this module creates is free to leave running. Virtual networks,
subnets, peerings, network security groups and route tables carry no hourly
charge, which is the whole reason ADR 0004 picked hub and spoke over Virtual
WAN for a lab on a personal card. The things that bill are in
[`terraform/90-optional-network/billable.tf`](../../90-optional-network/billable.tf),
behind flags.

## Why this is a module

One caller, which by the rule in [modules/README.md](../README.md) is not
enough. It got extracted anyway, for the same reason `subscription-vending`
did: a spoke is four subnets, a network security group, a route table, a
variable number of routes and two peerings, and nesting that inside a `for_each`
in a root module produces something nobody can read. Every landing zone the
platform vends adds a caller, so the number only goes up.

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
/24s and a /26, which reproduces
[docs/ip-plan.md](../../../docs/ip-plan.md) exactly. That is not cleverness for
its own sake: it makes it impossible to hand a spoke a subnet outside its own
allocation, which is the single mistake an address plan exists to prevent. The
Bicep module derives the same prefixes with `cidrSubnet`, and the two agree.

**The archetype is enforced by peering, not by the name.** `corp` gets a default
route to the firewall and `use_remote_gateways`, so it reaches on premises
through the hub. `online` gets neither and therefore cannot, no matter what it
is called. That is ADR 0003 as a deployment rather than as a convention.

**`use_remote_gateways` is gated on a gateway actually existing.** Azure rejects
the peering outright if the flag is true and the hub has no gateway, so the
caller ties it to the gateway flags rather than to the archetype alone.

**Routes are only written when there is a firewall.** A route to a next hop that
does not exist is a black hole, so `firewall_private_ip` being empty produces an
empty route table rather than a broken one. The table itself is always created,
so switching the firewall on later adds routes instead of restructuring
anything.

**Two subnets are deliberately left bare.** The Application Gateway subnet gets
no network security group and no route table. Application Gateway v2 needs
inbound 65200-65535 from `GatewayManager` to stay manageable, and a default
route to a firewall breaks its control plane, so both would do harm rather than
good until an actual gateway is deployed there. The audit assignment at the
intermediate root will report the subnet, correctly.
