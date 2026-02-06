output "resource_group_id" {
  value = azurerm_resource_group.sandbox.id
}

output "resource_group_name" {
  value = azurerm_resource_group.sandbox.name
}
output "persona_group_object_ids" {
  value = { for k, g in msgraph_resource.persona_group : k => g.id }
}