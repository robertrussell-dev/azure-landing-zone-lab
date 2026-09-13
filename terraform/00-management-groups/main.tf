# Management group hierarchy, written by hand so every group and parent is
# visible in one file. ADR 0007 covers why the ALZ pattern module isn't used.
#
# Azure allows six levels below the tenant root group; this uses three.

# ---------------------------------------------------------------------------
# Intermediate root
# ---------------------------------------------------------------------------
# Everything hangs off this, so subscriptions can be moved in and the tree
# reorganized without touching the tenant root group.
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

# Sandboxes are for experimentation, isolated from the hub, with permissive
# policy.
resource "azurerm_management_group" "sandboxes" {
  name                       = "${var.prefix}-sandboxes"
  display_name               = "Sandboxes"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# Decommissioned holds canceled subscriptions, locked down by policy until their
# retention window ends.
resource "azurerm_management_group" "decommissioned" {
  name                       = "${var.prefix}-decommissioned"
  display_name               = "Decommissioned"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# ---------------------------------------------------------------------------
# Tier 2: platform children
# ---------------------------------------------------------------------------
# Groups, not subscriptions placed directly under Platform, so a second
# connectivity subscription can be added later without reassigning policy.
#
# These four are identical in shape, so they're a loop.
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
# A copy of Corp with the same policy assignments set to DoNotEnforce. Adopted
# subscriptions start here and move to Corp once compliant. See ADR 0005.
resource "azurerm_management_group" "landing_zone_corp_audit" {
  name                       = "${var.prefix}-lz-corp-audit"
  display_name               = "Corp (audit only)"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}
