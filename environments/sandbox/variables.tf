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
  type        = string
  description = "Azure subscription ID for the sandbox environment. Set via a local, gitignored terraform.tfvars — do not default this to a real value."
}

# Not currently passed to any provider (msgraph auth uses az login / device
# code in this devcontainer) — reserved for when Azure AD app auth is added.
variable "azure_tenant_id" {
  type        = string
  description = "Azure tenant ID for the sandbox environment. Set via a local, gitignored terraform.tfvars — do not default this to a real value."
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
#6.2
variable "gcp_project_id" {
  type        = string
  description = "GCP project id for sandbox (can be placeholder for code-only)"
  default     = "CHANGE_ME_GCP_PROJECT_ID"
}

variable "gcp_name_prefix" {
  type        = string
  description = "Prefix for GCP IAM objects (service accounts)"
  default     = "iam"
}
variable "enable_aws" {
  type    = bool
  default = false
}

variable "enable_gcp" {
  type    = bool
  default = false
}
# --- Optional provider placeholders (allow validate/plan without real creds) ---

# AWS
variable "aws_access_key_id" {
  type        = string
  description = "Placeholder AWS access key for optional provider (override with real creds when enabling AWS)"
  default     = "DUMMY_ACCESS_KEY"
}

variable "aws_secret_access_key" {
  type        = string
  description = "Placeholder AWS secret key for optional provider (override with real creds when enabling AWS)"
  default     = "DUMMY_SECRET_KEY"
  sensitive   = true
}

# GCP
variable "gcp_region" {
  type        = string
  description = "GCP region for optional provider"
  default     = "us-central1"
}

variable "gcp_access_token" {
  type        = string
  description = "Placeholder GCP access token for optional provider (override with real token/ADC when enabling GCP)"
  default     = "DUMMY_GCP_TOKEN"
  sensitive   = true
}