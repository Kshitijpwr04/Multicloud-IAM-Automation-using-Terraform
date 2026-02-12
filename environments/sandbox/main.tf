module "azure_iam" {
  source = "../../modules/azure-iam"

  location            = var.location
  resource_group_name = var.resource_group_name
}
#5.2
module "aws_iam" {
  source = "../../modules/aws-iam"

  name_prefix                  = var.aws_name_prefix
  max_session_duration_seconds = var.aws_max_session_duration_seconds

  persona_to_policy_arns = {
    security_analyst   = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    auditor            = ["arn:aws:iam::aws:policy/SecurityAudit"]
    cloud_engineer     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    devsecops_engineer = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    break_glass        = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }
}