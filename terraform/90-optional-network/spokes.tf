# The spokes.
#
# One module call under for_each. The module could have been inlined, and the
# rule in terraform/modules/README.md says one caller is not enough to extract
# anything, but a spoke is four subnets, a network security group, a route
# table, a variable number of routes and two peerings, and nesting that inside
# a for_each in a root module produces something nobody can read. This is the
# same exception subscription-vending is: extracted for callers that do not
# exist yet, on a shape that will certainly gain them.

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

  # Empty while no firewall exists, which leaves the route table in place and
  # unpopulated rather than pointing traffic at nothing.
  firewall_private_ip = var.deploy_firewall ? azurerm_firewall.hub[0].ip_configuration[0].private_ip_address : ""

  # Gateway transit is the archetype. Corp reaches on premises through the
  # hub's gateway, Online was never given the transit and so cannot, and that
  # is enforcement rather than naming. Azure rejects the peering outright if
  # this is true and no gateway exists, so it is also gated on the flag.
  use_remote_gateways = each.value.archetype == "corp" && (var.deploy_vpn_gateway || var.deploy_expressroute_gateway)

  # Every archetype supernet except this spoke's own. One route per archetype
  # covers all 64 spokes that fit in it, which is why the address plan split
  # Corp and Online by block in the first place.
  peer_prefixes = [
    for archetype, supernet in var.archetype_supernets : supernet
    if archetype != each.value.archetype
  ]

  tags = {
    autoDelete = "false"
    archetype  = each.value.archetype
  }
}
