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

#3.3 adding azure roles to personas
locals {
  persona_to_azure_role = {
    security_analyst   = "Reader"
    auditor            = "Reader"
    cloud_engineer     = "Contributor"
    devsecops_engineer = "Contributor"
    break_glass        = "Owner"
  }
}
# Phase 4.2 — Group-based Azure RBAC assignments (to Entra persona groups)

/*resource "azurerm_role_assignment" "persona_groups" {
  for_each = local.persona_to_azure_role

  scope                = azurerm_resource_group.sandbox.id
  role_definition_name = each.value
  principal_id         = msgraph_resource.persona_group[each.key].id
}*/
#4.3 changed to exclude Break glass
resource "azurerm_role_assignment" "persona_groups" {
  for_each = {
    for k, v in local.persona_to_azure_role : k => v if k != "break_glass"
  }

  scope                = azurerm_resource_group.sandbox.id
  role_definition_name = each.value
  principal_id         = msgraph_resource.persona_group[each.key].id
}

###
#4.3 Break-glass: explicit, isolated RBAC assignment
resource "azurerm_role_assignment" "break_glass_owner" {
  scope                = azurerm_resource_group.sandbox.id
  role_definition_name = "Owner"
  principal_id         = msgraph_resource.persona_group["break_glass"].id
}