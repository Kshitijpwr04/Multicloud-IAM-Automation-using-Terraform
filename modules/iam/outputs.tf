output "role_assignment_id" {
  description = "Used for RBAC Role"
  value       = azurerm_role_assignment.this.id
}