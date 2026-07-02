#5.1 
variable "name_prefix" {
  type        = string
  description = "Prefix for AWS IAM role names"
  default     = "iam-persona"
}

variable "max_session_duration_seconds" {
  type        = number
  description = "Max AWS role session duration"
  default     = 3600
}

variable "persona_to_policy_arns" {
  type        = map(list(string))
  description = "Persona -> list of AWS managed policy ARNs"
}

#5.3
variable "use_permission_boundary" {
  type        = bool
  description = "Whether to apply a permission boundary to persona roles"
  default     = true
}

variable "permission_boundary_policy_arn" {
  type        = string
  description = "Existing IAM policy ARN to use as permission boundary (optional). If null, module creates a placeholder boundary policy."
  default     = null
}
#5.4
variable "break_glass_session_duration_seconds" {
  type        = number
  description = "Max session duration for break_glass role (short by design)"
  default     = 900
}