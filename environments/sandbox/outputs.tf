# Azure Outputs
output "azure_resource_group_name" {
  value = module.azure_iam.resource_group_name
}

output "azure_resource_group_id" {
  value = module.azure_iam.resource_group_id
}

# GCP Outputs (Phase 6)
output "gcp_automation_sa_email" {
  value = var.enable_gcp ? module.gcp_iam.automation_service_account_email : null
}

output "gcp_cicd_sa_email" {
  value = var.enable_gcp ? module.gcp_iam.cicd_service_account_email : null
}

# Phase 7 Debug Outputs
output "debug_desired_memberships_by_persona" {
  value = local.desired_memberships_by_persona
}

output "debug_active_user_emails" {
  value = keys(local.active_users_by_email)
}

output "debug_terminated_user_emails" {
  value = keys(local.terminated_users_by_email)
}