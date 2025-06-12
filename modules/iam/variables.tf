variable "scope" {
  description = "The Azure scope for the role assignment"
  type        = string
}

variable "role_definition_name" {
  description = "The built-in role to assign (e.g., Reader, Contributor)"
  type        = string
}

variable "principal_id" {
  description = "The object ID of the user, group, or service principal"
  type        = string
}