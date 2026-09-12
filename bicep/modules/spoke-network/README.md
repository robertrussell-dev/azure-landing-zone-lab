# spoke-network

One spoke virtual network: subnets derived from the spoke's own prefix, a
baseline network security group, a route table, and both halves of the peering
with the hub.

![Hub and spoke network](../../../docs/diagrams/hub-spoke-network.svg)

The Bicep counterpart of
[`terraform/modules/spoke-network`](../../../terraform/modules/spoke-network/).
Everything it creates is free to leave running, which is the reason ADR 0004
picked hub and spoke over Virtual WAN. The billable devices are in
[`bicep/90-optional-network/billable.bicep`](../../90-optional-network/billable.bicep),
behind flags.

## Usage

```bicep
module spoke '../modules/spoke-network/main.bicep' = [
  for s in spokes: {
    scope: hubResourceGroup
    name: 'spoke-${s.name}'
    params: {
      name: s.name
      location: location
      addressSpace: s.addressSpace
      archetype: s.archetype
      hubVirtualNetworkName: hubNetwork.outputs.virtualNetworkName
      firewallPrivateIp: billable.outputs.firewallPrivateIp
      useRemoteGateways: s.archetype == 'corp' && deployVpnGateway
      peerPrefixes: [ '10.2.0.0/16' ]
    }
  }
]
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | Short spoke name. Used in every resource name. |
| `location` | string | required | Region. |
| `addressSpace` | string | required | The spoke's whole prefix. Subnets are derived from it. |
| `archetype` | string | required | `corp` or `online`. Decides routing and gateway transit. |
| `hubVirtualNetworkName` | string | required | Hub to peer with, assumed to be in this resource group. |
| `firewallPrivateIp` | string | `''` | Empty leaves the route table in place and unpopulated. |
| `useRemoteGateways` | bool | `false` | Azure rejects the peering if this is true and the hub has no gateway. |
| `peerPrefixes` | array | `[]` | Other archetypes' supernets, routed to the firewall. |
| `tags` | object | `{}` | |

The resource group is the module's deployment scope, not a parameter.

## Outputs

| Name | Description |
|---|---|
| `virtualNetworkId` | Resource ID of the spoke. |
| `virtualNetworkName` | Name of the spoke. |
| `subnetPrefixes` | The derived prefixes, so the plan can be checked without reading deployed state. |

## Notes

**`cidrSubnet` and Terraform's `cidrsubnet` agree.** Both derive three /24s and
a /26 from the /22 and produce prefixes identical to
[docs/ip-plan.md](../../../docs/ip-plan.md). Deriving rather than listing makes
it impossible to hand a spoke a subnet outside its own allocation.

**Subnets are inline on the virtual network, never child resources.** Mixing the
two makes alternating deployments overwrite each other, which Microsoft
documents. That also means the network security group and route table are
attached inline rather than through separate association resources, which is the
visible difference from the Terraform module.

**A for-expression cannot go inside a ternary.** The peer routes only exist when
there is a firewall, and writing that as `condition ? [] : [for ...]` fails with
`BCP138`. `map()` with a lambda does the same job and is legal in that position.

**The archetype is enforced by peering, not by the name.** `corp` gets a default
route to the firewall and `useRemoteGateways`; `online` gets neither and
therefore cannot reach on premises. ADR 0003 as a deployment rather than a
convention.

**Two subnets are deliberately left bare.** The Application Gateway subnet gets
no network security group and no route table, because Application Gateway v2
needs inbound 65200-65535 from `GatewayManager` and a default route to a
firewall breaks its control plane. Both would do harm until a gateway is
actually deployed there.
