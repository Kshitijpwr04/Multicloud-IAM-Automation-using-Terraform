variable "project_id" {
  type        = string
  description = "GCP Project ID to apply IAM bindings"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for GCP IAM objects (service accounts)"
  default     = "iam"
}

variable "persona_to_role" {
  type        = map(string)
  description = "Persona -> predefined GCP role (v1)"
}

variable "persona_group_emails" {
  type        = map(string)
  description = "Persona -> Google Group email used for IAM bindings (can be placeholders for code-only)"
}