output "virtual_network_id" {
  description = "Resource ID of the spoke virtual network."
  value       = azurerm_virtual_network.this.id
}

output "virtual_network_name" {
  description = "Name of the spoke virtual network."
  value       = azurerm_virtual_network.this.name
}

output "address_space" {
  description = "The spoke's prefix, echoed back so a caller can build routes without recomputing it."
  value       = var.address_space
}

output "subnet_ids" {
  description = "Subnet resource IDs by short name: app, data, privateendpoints, appgw."
  value       = { for k, v in azurerm_subnet.this : k => v.id }
}

output "subnet_prefixes" {
  description = "The derived subnet prefixes, so the address plan can be checked against the plan document without reading state."
  value       = { for k, v in local.subnets : k => v.prefix }
}
