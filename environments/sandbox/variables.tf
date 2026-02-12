variable "location" {
  type        = string
  description = "Azure region for sandbox resources"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the sandbox resource group"
  default     = "rg-iam-sandbox"
}

variable "azure_subscription_id" {
  type    = string
  default = "c39ffe15-279e-4da2-b993-6931c591eeec"
}

variable "azure_tenant_id" {
  type    = string
  default = "028eb7df-cb19-417e-84ad-d40af9d0e53f"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the sandbox environment"
  default     = "us-east-1"
}
#5.2
variable "aws_name_prefix" {
  type        = string
  description = "Prefix for AWS IAM role names"
  default     = "iam-persona"
}

variable "aws_max_session_duration_seconds" {
  type        = number
  description = "Max AWS role session duration"
  default     = 3600
}