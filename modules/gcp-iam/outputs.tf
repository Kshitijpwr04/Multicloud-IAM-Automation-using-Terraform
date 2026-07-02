output "gcp_module_ready" {
  value = true
}

output "automation_service_account_email" {
  value = google_service_account.iam_automation.email
}

output "cicd_service_account_email" {
  value = google_service_account.cicd.email
}