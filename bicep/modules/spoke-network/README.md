# spoke-network

One spoke virtual network: subnets derived from the spoke's own prefix, a
baseline network security group, a route table, and both halves of the peering
with the hub.

![Hub and spoke network](../../../docs/diagrams/hub-spoke-network.svg)

The Bicep counterpart of
[`terraform/modules/spoke-network`](../../../terraform/modules/spoke-network/).
Everything it creates is free to leave running. The billable devices are in
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
| `subnetNsgPolicyAssignmentId` | string | `''` | The subnet NSG audit assignment. When set, `snet-appgw` gets a Waiver against it. |
| `appgwWaiverExpiresOn` | string | `2027-09-12T00:00:00Z` | When that waiver lapses. |
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
a /26 from the /22, matching [docs/ip-plan.md](../../../docs/ip-plan.md), so no
subnet can fall outside the spoke's allocation.

**Subnets are inline on the virtual network.** Mixing inline and child subnets
makes deployments overwrite each other. So the network security group and route
table are attached inline too, unlike the Terraform module's association
resources.

**A for-expression cannot go inside a ternary.** The peer routes only exist when
there is a firewall, and writing that as `condition ? [] : [for ...]` fails with
`BCP138`. `map()` with a lambda does the same job and is legal in that position.

**The archetype is enforced by peering.** `corp` gets a default route to the
firewall and `useRemoteGateways`; `online` gets neither, so it can't reach on
premises.

**The Application Gateway subnet is left bare**, with no network security group
or route table. Application Gateway v2 needs inbound 65200-65535 from
`GatewayManager`, and a default route to a firewall breaks its control plane.
It carries a Waiver against the subnet audit, with an expiry.
