# The spokes. A module despite having one caller, which breaks the rule in
# terraform/modules/README.md; that README says why.

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

  # Corp reaches on premises through the hub gateway; Online can't. Azure
  # rejects the peering if there's no gateway, so it's gated on the flag too.
  use_remote_gateways = each.value.archetype == "corp" && (var.deploy_vpn_gateway || var.deploy_expressroute_gateway)

  # Every archetype supernet except this spoke's own. One route per archetype
  # covers all 64 spokes that fit in it, which is why the address plan split
  # Corp and Online by block in the first place.
  peer_prefixes = [
    for archetype, supernet in var.archetype_supernets : supernet
    if archetype != each.value.archetype
  ]

  subnet_nsg_policy_assignment_id = local.subnet_nsg_assignment_id

  tags = {
    autoDelete = "false"
    archetype  = each.value.archetype
  }
}
