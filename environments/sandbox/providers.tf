terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.3"
    }
  }
}

# Azure
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

# Microsoft Graph (Entra)
provider "msgraph" {
  # Uses az login / device code auth in this devcontainer environment
}

# AWS (optional/aliased). Used only when enable_aws=true and module is instantiated.
provider "aws" {
  alias  = "optional"
  region = var.aws_region

  # Placeholder creds so validate/plan can run without real AWS credentials.
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

# GCP (optional/aliased). Used only when enable_gcp=true and module is instantiated.
provider "google" {
  alias        = "optional"
  project      = var.gcp_project_id
  region       = var.gcp_region
  access_token = var.gcp_access_token
}