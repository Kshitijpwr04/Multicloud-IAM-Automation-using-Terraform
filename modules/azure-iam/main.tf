resource "azurerm_resource_group" "sandbox" {
  name     = var.resource_group_name
  location = var.location
}

#3.2 to add RBAC Assignment to current user on the resource group
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "sandbox_reader" {
  scope                = azurerm_resource_group.sandbox.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}


