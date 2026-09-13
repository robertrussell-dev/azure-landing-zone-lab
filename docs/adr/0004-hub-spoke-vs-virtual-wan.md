# ADR 0004: Hub and spoke rather than Virtual WAN

Status: Accepted
Date: 2026-09-06

## Context

Azure landing zones support two network topologies and Microsoft treats both as
valid. Hub and spoke means you build and operate the hub virtual network, the
peerings, the route tables and any network virtual appliance. Virtual WAN means
Microsoft operates regional hubs for you, with any to any transitive routing
between connected virtual networks and branches.

Both carry traffic. The difference is who does the routing work, and what it
costs to have the capability sitting there.

## Decision

**Hub and spoke, for this platform.**

The reason is specific to a lab and doesn't generalize. The criteria a
production estate should use are set out separately below.

## The cost difference

Retail prices, West US 2, USD, from the Azure retail prices API on 2026-09-06.

| Item | Price | Standing monthly cost |
|---|---|---|
| Virtual WAN Standard Hub Unit | 0.25 per hour | about 182 |
| Virtual WAN Routing Infrastructure Unit | 0.10 per hour | about 73 |
| Virtual WAN Standard Hub data processing | 0.02 per GB | usage |
| Virtual network and peering, at rest | no hourly charge | 0 |
| Azure Firewall Standard, secured virtual hub | 1.25 per hour | about 912 |
| VPN Gateway VpnGw5 | 3.65 per hour | about 2,665 |

What decides it here: **a Virtual WAN hub bills by the hour just for existing,
and virtual networks and peerings bill nothing at rest.** The hub and spoke
networks can stay deployed on a personal card, with only the billable devices
brought up on demand. A Virtual WAN hub can't.

## Why that reason does not generalize

About 182 dollars a month is a rounding error to any organization with a
platform team, so the lab's reason is set aside and the criteria below are the
ones a production estate would use.

## Microsoft's selection criteria

Microsoft doesn't name a default. It gives conditions for each, including a
numeric threshold.

**Virtual WAN** when any of these apply:

- Resources across several Azure regions requiring global connectivity between
  virtual networks in those regions and multiple on premises locations.
- An SD-WAN deployment integrating a large scale branch network into Azure, or
  **more than 30 branch sites** needing native IPSec termination.
- Transitive routing required between VPN and ExpressRoute, for example remote
  branches on site to site VPN needing to reach an ExpressRoute connected
  datacenter through Azure.

**Traditional hub and spoke** when any of these apply:

- Deployment across one or several regions, with some cross region traffic
  expected, but no requirement for a full mesh across all regions.
- A low number of branch locations per region, **fewer than 30 IPSec site to
  site tunnels**.
- A requirement for full control and granularity to configure Azure network
  routing policy manually.

Thirty site to site tunnels is the practical dividing line, and a platform
team can answer that at design time.

## What the choice actually trades

Underneath the criteria, the trade is operational effort against control, plus
cost.

Hub and spoke means the platform team owns routing. Route tables and user
defined routes on every spoke, next hop to the inspection appliance, route
propagation on the gateway subnet, and non transitive peering that has to be
arranged for every path. That's a standing operational load, and when it fails
it needs someone who understands it.

Virtual WAN removes most of that. Regional hubs are managed, any to any
transitive routing between connected networks is the default rather than
something constructed, and branch connectivity scales without a design per
site. In exchange you work inside its routing model, and a requirement it can't
express becomes a problem.

An organization with 200 branches choosing hub and spoke and one with three
spokes in one region paying for a managed hub are both wrong, in opposite
directions.

## No spoke to spoke peering

This applies whichever topology is chosen.

Spokes are peered to the hub and never to each other. Peering isn't
transitive, so without a route table sending spoke to spoke traffic through the
hub, it doesn't flow at all. Direct spoke peering would make it flow and skip
central inspection. Routing every path through the hub means one place sees
east west traffic.

The cost is a latency hop, and the hub appliance becomes a single point of
failure that has to be designed for.

## Consequences

- The free network layer stays deployed; billable devices are brought up on
  demand and taken down the same day.
- Route tables and user defined routes are the platform team's responsibility
  and the main source of routing incidents.
- A second region means designing inter hub connectivity by hand, which is the
  work Virtual WAN would absorb. A second region is the trigger to revisit this.
- A production estate should apply the criteria above. The answer here follows
  from a constraint it doesn't have.
