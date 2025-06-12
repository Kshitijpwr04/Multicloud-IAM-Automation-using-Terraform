
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}

provider "aws" {
  region                  = "us-east-1"
  access_key              = var.aws_access_key
  secret_key              = var.aws_secret_key
}

module "iam_assignment" {
  source = "../../modules/iam"

  scope                = azurerm_resource_group.dev_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_user.example.id
}