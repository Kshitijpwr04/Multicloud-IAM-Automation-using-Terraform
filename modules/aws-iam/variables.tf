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