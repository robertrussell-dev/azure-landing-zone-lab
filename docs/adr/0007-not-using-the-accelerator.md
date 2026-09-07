# ADR 0007: Not using the landing zone accelerator

Status: Proposed
Date: 2026-09-06

## Context

Microsoft ships an Azure landing zone accelerator, and `Azure/avm-ptn-alz/azurerm`
is the maintained Terraform pattern module for it. Either would deploy this
management group hierarchy, plus several hundred policy definitions and
assignments, in a single apply.

This platform does not use them. Anyone arriving later will want to know
whether that was deliberate.

## Decision

**Hand roll the hierarchy, the policy assignments and the subscription
vending.**

This is not a judgement that the accelerator is wrong. For an estate that needs
governance breadth, it is the correct choice and hand rolling is not.

## Why

This platform was built to develop operational understanding of the mechanics
before adopting a prebuilt set of them. Introduce too much prebuilt template
before understanding it and the result is harder to reason about and harder to
debug, not easier.

The principle underneath that: **you cannot operate what you cannot debug.**
The accelerator assigns several hundred policies. When one of them blocks a
release, someone has to know why it exists, at what scope it is assigned, and
whether the correct response is an exemption, a scope change, or refusing the
request. Deploying that set without understanding the mechanics produces an
estate nobody can reason about, and the first time that matters is during an
incident.

## What building it surfaced

These appeared only because something failed. A successful accelerator run
produces none of them:

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
  subscription reports no policy compliance at all, and the silence is
  indistinguishable from a scan that has not run.
- A Modify policy and Terraform will contend over the same tag indefinitely
  unless an owner for that field is declared.

Each is knowledge required to operate an accelerator deployed estate.

## What it costs

**Five policy assignments against the accelerator's several hundred.** This is
a demonstration of policy mechanics, not a governance baseline. An estate that
needs breadth should take it from the accelerator rather than reproduce it by
hand.

**Maintenance.** The accelerator tracks Azure as services are added. This
configuration does not, and will drift within months.

ADR 0006 recommends `Deploy-Private-DNS-Zones`, an accelerator initiative, as
the right implementation of centralised private DNS. That is the shape of the
position: take breadth from the maintained thing, and understand it well enough
to explain any part of it.

## Consequences

- Every policy assignment, scope choice and enforcement mode here can be
  explained individually.
- The policy set is not a governance baseline, and the README says so.
- Operating the accelerator is a separate skill, with substantial configuration
  surface of its own, and building these parts by hand does not exercise it.
- Adopting the accelerator later is the expected path rather than a reversal.
  The trigger is demonstrated proficiency operating what is here, plus a real
  need for the breadth and standardisation it provides. This decision would
  then be revised, and the mechanics learned here are what make its output
  reviewable.
