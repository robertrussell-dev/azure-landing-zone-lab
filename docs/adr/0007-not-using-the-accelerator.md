# ADR 0007: Not using the landing zone accelerator

Status: Accepted
Date: 2026-09-06

## Context

Microsoft ships an Azure landing zone accelerator, and `Azure/avm-ptn-alz/azurerm`
is the maintained Terraform pattern module for it. Either would deploy this
management group hierarchy, plus several hundred policy definitions and
assignments, in a single apply.

This platform doesn't use them, and this records why.

## Decision

**Hand roll the hierarchy, the policy assignments and the subscription
vending.**

The accelerator isn't wrong. For an organization that needs governance breadth,
it's the right choice and hand rolling isn't.

## Why

I built this to understand the mechanics before adopting a prebuilt set of
them.

The accelerator assigns several hundred policies. When one blocks a release,
someone has to know why it exists, where it's assigned, and whether the answer
is an exemption, a scope change, or refusing the request. Without understanding
the mechanics, that first comes up during an incident.

## What building it surfaced

Each of these turned up because something failed, which an accelerator run
wouldn't have shown:

- The built in "Subnets should be associated with a Network Security Group"
  permits only `AuditIfNotExists` or `Disabled`. It cannot be used as a Deny,
  which is how it is frequently described.
- The built in tagging Modify policy requires **Contributor** for its managed
  identity, not Tag Contributor. Assigning it at an intermediate root grants a
  policy created principal Contributor across the entire hierarchy.
- `enforcementMode = DoNotEnforce` writes **no Activity log entries**, so an
  audit only period cannot be measured by counting events that would have been
  denied.
- A newly vended subscription refuses every write, despite showing its creator
  as Owner, until it is placed in a management group.
- `Microsoft.PolicyInsights` is unregistered by default. Without it a
  subscription reports no policy compliance, which looks the same as a scan
  that hasn't run.
- A Modify policy and Terraform will contend over the same tag indefinitely
  unless an owner for that field is declared.

Operating an environment the accelerator deployed needs all of these.

## What it costs

**Eight policy assignments against the accelerator's several hundred.** This
shows policy mechanics, not a governance baseline. An organization that needs
breadth should take it from the accelerator.

**Maintenance.** The accelerator tracks Azure as services are added. This
configuration does not, and will drift within months.

ADR 0006 recommends `Deploy-Private-DNS-Zones`, an accelerator initiative, as
the right implementation of centralized private DNS: take breadth from the
maintained thing, and understand it well enough to explain any part of it.

## Consequences

- Every policy assignment, scope choice and enforcement mode here can be
  explained individually.
- The policy set is not a governance baseline, and the README says so.
- Operating the accelerator is a separate skill, with substantial configuration
  surface of its own, and building these parts by hand does not exercise it.
- Adopting the accelerator later is the expected path, not a reversal. The
  trigger is a real need for its breadth, and what's learned here is what makes
  its output reviewable.
