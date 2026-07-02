# Phase 6 — GCP IAM v1

# Automation service accounts (used later for CI/CD, evidence export, etc.)
resource "google_service_account" "iam_automation" {
  account_id   = "${var.name_prefix}-automation"
  display_name = "IAM Automation Service Account"
}

resource "google_service_account" "cicd" {
  account_id   = "${var.name_prefix}-cicd"
  display_name = "CI/CD Service Account"
}

# Persona-based project IAM bindings (using Google Groups)
# Note: group emails can be placeholders for code-only commits.
resource "google_project_iam_member" "persona_bindings" {
  for_each = var.persona_to_role

  project = var.project_id
  role    = each.value
  member  = "group:${var.persona_group_emails[each.key]}"
}