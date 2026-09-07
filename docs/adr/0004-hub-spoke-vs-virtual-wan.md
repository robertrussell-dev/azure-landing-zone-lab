# ADR 0004: Hub and spoke rather than Virtual WAN

Status: Proposed
Date: 2026-09-06

## Context

Azure landing zones support two network topologies and Microsoft treats both as
valid. Hub and spoke means you build and operate the hub virtual network, the
peerings, the route tables and any network virtual appliance. Virtual WAN means
Microsoft operates regional hubs for you, with any to any transitive routing
between connected virtual networks and branches.

The choice is not primarily technical. Both carry traffic. The difference is
who does the routing work and what it costs to have the capability sitting
there.

## Decision

**Hub and spoke, for this platform.**

The reasons are specific to a lab and do not generalise. The criteria that
would apply to a production estate are set out below, separately.

## The cost difference is real and measurable

Retail prices, West US 2, USD, checked against the Azure retail prices API on
2026-09-06. Verify before reusing these, they move.

| Item | Price | Standing monthly cost |
|---|---|---|
| Virtual WAN Standard Hub Unit | 0.25 per hour | about 182 |
| Virtual WAN Routing Infrastructure Unit | 0.10 per hour | about 73 |
| Virtual WAN Standard Hub data processing | 0.02 per GB | usage |
| Virtual network and peering, at rest | no hourly charge | 0 |
| Azure Firewall Standard, secured virtual hub | 1.25 per hour | about 912 |
| VPN Gateway VpnGw5 | 3.65 per hour | about 2,665 |

The line that decides it here: **a Virtual WAN hub bills by the
hour for existing, and a hub and spoke topology built from virtual networks and
peerings bills nothing at rest.** Virtual networks, subnets, peerings and
private DNS zones can be left deployed indefinitely on a personal card. A
Virtual WAN hub cannot.

That is what makes the deploy, screenshot, destroy approach in Phase 4 possible
at all, and it is why the network stack here is not left running.

## Why that reason does not generalise

About 182 dollars a month is a rounding error to any organisation with a
platform team. Presenting a lab's cost constraint as the enterprise argument
would be dishonest. The lab reason is set aside here, and the decision is
examined on the criteria that would apply to a production estate.

## Microsoft's selection criteria

Microsoft does not name a default. It gives conditions for each, and the
numeric threshold is the useful part.

**Virtual WAN** when any of these apply:

- Resources across several Azure regions requiring global connectivity between
  virtual networks in those regions and multiple on premises locations.
- An SD-WAN deployment integrating a large scale branch network into Azure, or
  **more than 30 branch sites** needing native IPSec termination.
- Transitive routing required between VPN and ExpressRoute, for example remote
  branches on site to site VPN needing to reach an ExpressRoute connected
  datacentre through Azure.

**Traditional hub and spoke** when any of these apply:

- Deployment across one or several regions, with some cross region traffic
  expected, but no requirement for a full mesh across all regions.
- A low number of branch locations per region, **fewer than 30 IPSec site to
  site tunnels**.
- A requirement for full control and granularity to configure Azure network
  routing policy manually.

Thirty site to site tunnels is the practical dividing line, and it is a
question a platform team can answer at design time rather than a matter of
taste.

## What the choice actually trades

Underneath the criteria the trade is operational effort against control, and
cost sits on top of it.

Hub and spoke means the platform team owns routing. Route tables and user
defined routes on every spoke, next hop to the inspection appliance, route
propagation on the gateway subnet, and non transitive peering that has to be
arranged deliberately for every path. That is a standing operational load and
it fails in ways that need someone who understands it.

Virtual WAN removes most of that. Regional hubs are managed, any to any
transitive routing between connected networks is the default rather than
something constructed, and branch connectivity scales without a design per
site. In exchange you work inside its routing model, so a requirement it does
not express becomes a problem rather than a configuration.

Neither is the sophisticated choice. The organisation with 200 branches
choosing hub and spoke and the organisation with three spokes in one region
paying for a managed hub are both getting it wrong, in opposite directions.

## No spoke to spoke peering

Independent of the topology choice, and the part people get wrong.

Spokes are peered to the hub and never to each other. Virtual network peering
is not transitive, so this is not merely a convention: without a route table
sending spoke to spoke traffic through the hub, that traffic does not flow at
all.

Direct spoke to spoke peering would make it flow, and would bypass central
inspection. Every path between workloads crosses the hub deliberately, so that
one place sees east west traffic. The peering topology is the enforcement
mechanism, not a diagram convention.

The cost is a latency hop and a dependency on the hub appliance being
available, which becomes a single point of failure that has to be designed for.
That is the trade being made, and it is made on purpose.

## Consequences

- The network stack is deployed on demand and destroyed the same day. Nothing
  about the topology choice would survive a move to Virtual WAN unexamined.
- Route tables and user defined routes are the platform team's responsibility
  and the main source of routing incidents.
- Adding a second region means designing inter hub connectivity by hand, which
  is precisely the work Virtual WAN would have absorbed. A second region is
  the trigger to reopen this decision.
- The criteria above are what a production estate should apply. The answer
  reached here follows from a constraint a production estate does not have.
