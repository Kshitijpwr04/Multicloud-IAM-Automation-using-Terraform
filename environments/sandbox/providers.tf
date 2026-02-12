terraform {
  required_version = ">= 1.5.0"

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
    #4.1 enable us to add entra users and groups
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.3"
    }
  }
}

# Azure: uses Azure CLI auth (since you logged in with `az login`)
provider "azurerm" {
  features {}

  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
}

# AWS: stub provider for Phase 2 validation (no resources yet)
provider "aws" {
  region = var.aws_region
}

# GCP: stub provider for Phase 2 validation (no resources yet)
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "msgraph" {}