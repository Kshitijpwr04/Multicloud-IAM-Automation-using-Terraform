module "azure_iam" {
  source = "../../modules/azure-iam"

  location            = var.location
  resource_group_name = var.resource_group_name
}