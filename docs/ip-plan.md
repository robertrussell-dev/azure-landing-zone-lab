# Worked IP plan: hub and spoke landing zone

The address plan behind [`terraform/90-optional-network`](../terraform/90-optional-network/)
and [`bicep/90-optional-network`](../bicep/90-optional-network/). Both trees
derive their prefixes from the parent range rather than listing them, so what
gets deployed and what's written here can't drift apart.

The numbers are picked to be easy to reason about, not because they're the only
correct answer.

![Hub and spoke network](diagrams/hub-spoke-network.svg)

The diagram above is what the code actually builds. The rest of this page is the
reasoning that got there.

---

## The whole plan on one page

```
10.0.0.0/12                 AZURE TOTAL      10.0.0.0 - 10.15.255.255
|
+-- 10.0.0.0/14             REGION 1 (primary)
|   |
|   +-- 10.0.0.0/16         PLATFORM
|   |   |
|   |   +-- 10.0.0.0/20     Hub VNet
|   |   |   |
|   |   |   +-- 10.0.0.0/26      GatewaySubnet          (/27 min, /26 for ER+VPN)
|   |   |   +-- 10.0.0.64/26     AzureFirewallSubnet    (/26 required)
|   |   |   +-- 10.0.0.128/26    AzureFirewallManagementSubnet  (/26, forced tunneling)
|   |   |   +-- 10.0.0.192/26    AzureBastionSubnet     (/26 min)
|   |   |   +-- 10.0.1.0/26      RouteServerSubnet      (/26 min, BGP NVA only)
|   |   |   +-- 10.0.1.64/28     DNS Private Resolver inbound   (delegated)
|   |   |   +-- 10.0.1.80/28     DNS Private Resolver outbound  (delegated)
|   |   |   +-- 10.0.2.0/24      Shared private endpoints
|   |   |   +-- 10.0.3.0/24      Shared services / jumpboxes
|   |   |   +-- 10.0.4.0/22 +    reserved for hub growth
|   |   |
|   |   +-- 10.0.16.0/20    Platform spokes
|   |       +-- 10.0.16.0/24     Identity subscription
|   |       +-- 10.0.17.0/24     Management subscription
|   |       +-- 10.0.18.0/24     Security subscription
|   |       +-- 10.0.19.0/24 +   reserved
|   |
|   +-- 10.1.0.0/16         CORP landing zones     (routed to on-prem)
|   |   +-- 10.1.0.0/22          payments-prod
|   |   |   +-- 10.1.0.0/24          app
|   |   |   +-- 10.1.1.0/24          data
|   |   |   +-- 10.1.2.0/24          private endpoints
|   |   |   +-- 10.1.3.0/26          Application Gateway
|   |   |   +-- 10.1.3.64/26 +       reserved
|   |   +-- 10.1.4.0/22          payments-nonprod
|   |   +-- 10.1.8.0/22          eligibility-prod
|   |   +-- 10.1.12.0/22         eligibility-nonprod
|   |   +-- 10.1.16.0/22 +       next spoke, sequential   (64 spokes fit)
|   |
|   +-- 10.2.0.0/16         ONLINE landing zones   (internet facing, no on-prem route)
|   |   +-- 10.2.0.0/22          public-portal-prod
|   |   +-- 10.2.4.0/22 +        sequential
|   |
|   +-- 10.3.0.0/16         reserved: sandbox, future archetypes
|
+-- 10.4.0.0/14             REGION 2 (DR, identical internal layout)
+-- 10.8.0.0/14             reserved, region 3
+-- 10.12.0.0/14            reserved, region 4


OUTSIDE the Azure allocation
  10.200.0.0/13    on-prem
  192.168.0.0/16   on-prem
  172.20.0.0/16    Partner A (advertised into hub)
  172.31.0.0/16    AKS serviceCidr, cluster-internal, never routed
  172.17.0.0/16    AVOID, Docker default bridge
```

## How traffic actually moves through it

```
                  on-prem 10.200.0.0/13        Partner A 172.20.0.0/16
                          |                             |
                    ExpressRoute (primary)              |
                    S2S VPN (failover)                  |
                          |                             |
                  +-------v-----------------------------v-------+
                  |            HUB VNet  10.0.0.0/20            |
                  |                                             |
                  |   Gateway  |  Azure Firewall  |  DNS zones  |
                  +------+--------------------------------+-----+
                         |                                |
           peering       |                                |    peering
           + gateway     |                                |    NO gateway
           transit       |                                |    transit
                         |                                |
              +----------v-----------+       +------------v---------+
              |  CORP  10.1.0.0/16   |       | ONLINE  10.2.0.0/16  |
              |                      |       |                      |
              |  UDR 0.0.0.0/0 ------+-------+---> firewall         |
              |  reaches on-prem     |       |  no on-prem route    |
              +----------------------+       +----------------------+

  Spoke to spoke does NOT work by default. Peering is not transitive.
  Each spoke needs a UDR sending the peer prefix to the firewall private
  IP in the hub, plus a matching firewall rule. Because CORP is one /16
  and ONLINE is another, those rules stay short.

  The archetype is enforced by gateway transit, not by naming. ONLINE
  spokes cannot reach on-prem because they were never given the transit.
```

---

## Step 0: before picking any numbers

Collect the existing on-prem ranges, any other cloud ranges, and anything a
partner might advertise in. Overlap is the one mistake that can't be fixed later
without renumbering, and renumbering a live estate is a project rather than a
change.

This example assumes:

* On-prem uses `10.200.0.0/13` and `192.168.0.0/16`
* Partner A advertises `172.20.0.0/16`
* Azure gets the whole of `10.0.0.0/12`, which is `10.0.0.0` to `10.15.255.255`

`172.17.0.0/16` is avoided everywhere, because it's Docker's default bridge
network and a container host lands on it sooner or later.

---

## Step 1: carve by region, not by workload

The usual mistake is allocating the first spoke out of the front of the range
and then discovering a second region needs contiguous space. Regions get
reserved first.

| Allocation | Range | Purpose |
|---|---|---|
| `10.0.0.0/14` | 10.0.0.0 to 10.3.255.255 | Region 1, primary |
| `10.4.0.0/14` | 10.4.0.0 to 10.7.255.255 | Region 2, DR |
| `10.8.0.0/14` | 10.8.0.0 to 10.11.255.255 | Reserved, region 3 |
| `10.12.0.0/14` | 10.12.0.0 to 10.15.255.255 | Reserved, region 4 |

Each /14 is 262,144 addresses, which is absurd for most estates. That's fine.
RFC1918 space costs nothing and running out of it costs a lot.

If this were Azure Government the regions would be USGov Virginia, USGov
Arizona, and USGov Texas. Same plan, different names.

---

## Step 2: carve within Region 1

`10.0.0.0/14` splits into four /16s:

| Allocation | Purpose |
|---|---|
| `10.0.0.0/16` | Platform: hub plus shared platform spokes |
| `10.1.0.0/16` | Corp landing zones, routed to on-prem |
| `10.2.0.0/16` | Online landing zones, internet facing, no on-prem route |
| `10.3.0.0/16` | Reserved: sandbox, future archetypes |

Splitting Corp from Online by address block isn't cosmetic. It means a single
route or firewall rule can cover an entire archetype instead of enumerating
spokes.

---

## Step 3: the hub

Hub VNet: `10.0.0.0/20`, which is 10.0.0.0 to 10.0.15.255, 4096 addresses.

| Subnet | Range | Notes |
|---|---|---|
| `GatewaySubnet` | `10.0.0.0/26` | /27 is the minimum, /26 gives room for ExpressRoute and VPN coexistence |
| `AzureFirewallSubnet` | `10.0.0.64/26` | /26 required, name is mandatory |
| `AzureFirewallManagementSubnet` | `10.0.0.128/26` | /26 required, only needed with forced tunneling |
| `AzureBastionSubnet` | `10.0.0.192/26` | /26 minimum, name is mandatory |
| `RouteServerSubnet` | `10.0.1.0/26` | /26 minimum, only worth it with a BGP-speaking NVA |
| DNS Private Resolver inbound | `10.0.1.64/28` | delegated subnet |
| DNS Private Resolver outbound | `10.0.1.80/28` | delegated subnet |
| Shared private endpoints | `10.0.2.0/24` | |
| Shared services | `10.0.3.0/24` | jumpboxes, tooling |
| Reserved | `10.0.4.0/22` and up | future hub growth |

The four /26s tile `10.0.0.0/24` exactly. That's deliberate, and it's the reason
the hub subnets can all be derived from one parent prefix in code.

`RouteServerSubnet` is a /26, not a /27. Plenty of older material says /27 and
Microsoft's own DDoS tutorial still shows one, but the current Route Server
quickstarts all state /26 minimum and a /27 fails at create time. It matters
here because a /26 starting at `10.0.1.0` runs to `10.0.1.63`, which is exactly
where the two DNS Private Resolver /28s sat in an earlier draft of this plan.
Widening the subnet without moving them is a silent overlap, so the resolver
endpoints start at `10.0.1.64`.

Subnet names in backticks are literal. Azure won't attach the service if they're
spelled anything else, and the failure is a deployment error rather than a
warning.

Platform spokes for Identity, Management, and Security get /24s out of
`10.0.16.0/20`.

---

## Step 4: the spokes

Standard allocation: **one /22 per workload per environment**. That's 1024
addresses, enough for almost anything, and small enough that a /16 holds 64 of
them.

Corp landing zones out of `10.1.0.0/16`:

| Spoke | Range |
|---|---|
| payments-prod | `10.1.0.0/22` |
| payments-nonprod | `10.1.4.0/22` |
| eligibility-prod | `10.1.8.0/22` |
| eligibility-nonprod | `10.1.12.0/22` |
| next spoke | `10.1.16.0/22` |

Inside one spoke, `10.1.0.0/22`:

| Subnet | Range | Usable |
|---|---|---|
| app | `10.1.0.0/24` | 251 |
| data | `10.1.1.0/24` | 251 |
| private endpoints | `10.1.2.0/24` | 251 |
| Application Gateway | `10.1.3.0/26` | 59 |
| reserved | `10.1.3.64/26` and up | |

Azure reserves five addresses in every subnet: the network address, two for
routing, one for internal DNS mapping, and broadcast. So a /24 gives 251 rather
than 256, and a /29 gives 3.

---

## Step 5: the AKS trap

This is the part that catches people out, and it's worth settling before anyone
deploys a cluster into a spoke.

**Azure CNI** assigns every pod an IP from the node subnet. Sizing is roughly
`nodes x (maxPods + 1)`. A 50 node cluster at 30 pods per node needs over 1550
addresses, so a /21 for the node subnet alone. That's how a team burns a /22 on
a single cluster.

**Azure CNI Overlay** puts pods on a separate private CIDR that never touches
VNet space. Nodes consume VNet IPs, pods don't. For a greenfield build this is
usually the right call, and it's what makes an address plan survivable.

**The serviceCidr conflict.** AKS defaults its service CIDR to `10.0.0.0/16`
with dnsServiceIP `10.0.0.10`. In the plan above that collides head on with the
hub. Override it and put the service CIDR outside the whole `10.0.0.0/12`
allocation, `172.31.0.0/16` for example. It's cluster-internal and never routed,
so it only has to avoid overlapping anything the cluster needs to reach.

It gets its own step because it's a real production failure rather than a
theoretical one.

---

## Step 6: routing that follows from the plan

Because Corp is `10.1.0.0/16` and Online is `10.2.0.0/16`, the rules stay short.

* Spoke to spoke isn't automatic. VNet peering is not transitive, so each spoke
  gets a UDR sending the other spoke's prefix to the Azure Firewall private IP
  in the hub, and the firewall needs a matching rule.
* Corp spokes get a default route `0.0.0.0/0` to the firewall for forced
  tunneling and inspection.
* Corp spokes use gateway transit to reach on-prem through the hub's
  ExpressRoute or VPN gateway.
* Online spokes don't get gateway transit at all, which is the actual
  enforcement of the archetype rather than a naming convention.
* On-prem `10.200.0.0/13` and Partner A `172.20.0.0/16` are advertised into the
  hub and reach spokes through the firewall only.

---

## The short version

The order this gets built in:

1. Find out what on-prem uses, and whether there's a second region or a DR
   requirement.
2. Reserve `10.0.0.0/12` for Azure, split into a /14 per region.
3. Split the region /14 into /16s: platform, Corp, Online, reserved.
4. Hub is a /20 out of platform, with the mandatory reserved subnet names.
5. Every spoke is a /22, allocated sequentially, never hand-picked.
6. Settle the AKS serviceCidr and CNI sizing question early.

The reasoning matters more than the specific numbers. What holds the plan
together is reserving before allocating, knowing the mandatory subnet names and
minimum sizes, and remembering that peering doesn't route on its own.
