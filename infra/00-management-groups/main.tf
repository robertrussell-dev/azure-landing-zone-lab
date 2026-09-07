# Management group hierarchy, composed by hand.
#
# The Azure Verified Modules ALZ pattern module would generate this and a great
# deal more. It is not used here for the hierarchy, because the point of this
# directory is that every group and every parent relationship is visible and
# explainable in one file. See docs/adr for the reasoning and the README for
# where AVM is used instead.
#
# Depth note: Azure allows six levels below the tenant root group. This tree
# uses three, which leaves room to insert a level later without restructuring.

# ---------------------------------------------------------------------------
# Intermediate root
# ---------------------------------------------------------------------------
# Everything hangs off this, not off the tenant root group directly. Building
# under an intermediate root is what allows existing subscriptions to be moved
# in, and the structure below to be reorganised, without ever touching the
# tenant root group.
#
# Omitting parent_management_group_id places this under the tenant root group.
resource "azurerm_management_group" "intermediate_root" {
  name         = var.prefix
  display_name = var.intermediate_root_display_name
}

# ---------------------------------------------------------------------------
# Tier 1: the four top level groups
# ---------------------------------------------------------------------------
# Written as explicit resources rather than a loop. There are only four, they
# are not interchangeable, and each one exists for a different reason.

# Platform holds the subscriptions that serve every other landing zone.
resource "azurerm_management_group" "platform" {
  name                       = "${var.prefix}-platform"
  display_name               = "Platform"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# Landing zones holds workload subscriptions, grouped by archetype.
resource "azurerm_management_group" "landing_zones" {
  name                       = "${var.prefix}-landingzones"
  display_name               = "Landing zones"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# Sandboxes are deliberately loose. Subscriptions here are for experimentation
# and are isolated from the hub, so policy here is permissive by design rather
# than by neglect.
resource "azurerm_management_group" "sandboxes" {
  name                       = "${var.prefix}-sandboxes"
  display_name               = "Sandboxes"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# Decommissioned holds subscriptions on their way out. Cancelled subscriptions
# are moved here so that policy can keep them locked down during the retention
# window before deletion becomes permanent.
resource "azurerm_management_group" "decommissioned" {
  name                       = "${var.prefix}-decommissioned"
  display_name               = "Decommissioned"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# ---------------------------------------------------------------------------
# Tier 2: platform children
# ---------------------------------------------------------------------------
# Each of these is a management group that will contain a subscription, not a
# subscription placed directly under Platform. Microsoft describes Connectivity
# as "dedicated subscriptions, commonly a single subscription for most
# organizations". The management group layer exists so a second connectivity
# subscription can be added later without restructuring the tree or reassigning
# policy.
#
# These four are structurally identical, so they are written as a loop. The
# locals map keeps the data separate from the resource shape.
locals {
  platform_children = {
    identity     = "Identity"
    management   = "Management"
    connectivity = "Connectivity"
    security     = "Security"
  }

  # Workload archetypes, not environments and not business units.
  #
  #   corp   requires hybrid connectivity routed through the hub
  #   online does not require corporate connectivity
  #   local  is for Azure Local clusters
  #
  # Environments (dev, test, prod) are subscriptions inside these groups, not
  # management groups of their own. See ADR 0002.
  landing_zone_archetypes = {
    corp   = "Corp"
    online = "Online"
    local  = "Local"
  }
}

resource "azurerm_management_group" "platform_child" {
  for_each = local.platform_children

  name                       = "${var.prefix}-platform-${each.key}"
  display_name               = each.value
  parent_management_group_id = azurerm_management_group.platform.id
}

# ---------------------------------------------------------------------------
# Tier 2: landing zone archetypes
# ---------------------------------------------------------------------------
resource "azurerm_management_group" "landing_zone_archetype" {
  for_each = local.landing_zone_archetypes

  name                       = "${var.prefix}-lz-${each.key}"
  display_name               = each.value
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

# ---------------------------------------------------------------------------
# Brownfield adoption target
# ---------------------------------------------------------------------------
# A duplicate of the Corp archetype carrying the same policy assignments with
# enforcementMode set to DoNotEnforce.
#
# Subscriptions being adopted from an existing estate are placed here first.
# They are evaluated against the policies they will eventually be held to,
# and nothing is blocked while that assessment happens. When compliance is
# acceptable the subscription moves to Corp, and enforcement begins without
# any policy being rewritten.
#
# This duplicates the hierarchy and the assignments. It does not duplicate any
# workload, so it costs nothing. See ADR 0005.
resource "azurerm_management_group" "landing_zone_corp_audit" {
  name                       = "${var.prefix}-lz-corp-audit"
  display_name               = "Corp (audit only)"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}
