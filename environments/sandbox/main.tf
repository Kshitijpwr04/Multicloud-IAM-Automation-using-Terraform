
# Phase 7 — Unified Persona Engine

locals {
  # --- YAML loaded in Phase 7.1 ---
  personas = yamldecode(file("${path.root}/../../identities/personas.yaml"))
  users    = yamldecode(file("${path.root}/../../identities/users.yaml"))

  # --- 7.2: Persona → Cloud mappings (v1) ---
  azure_persona_to_role = {
    security_analyst   = "Reader"
    auditor            = "Reader"
    cloud_engineer     = "Contributor"
    devsecops_engineer = "Contributor"
    break_glass        = "Owner"
  }

  aws_persona_to_policy_arns = {
    security_analyst   = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    auditor            = ["arn:aws:iam::aws:policy/SecurityAudit"]
    cloud_engineer     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    devsecops_engineer = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    break_glass        = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  gcp_persona_to_role = {
    security_analyst   = "roles/viewer"
    auditor            = "roles/viewer"
    cloud_engineer     = "roles/editor"
    devsecops_engineer = "roles/editor"
    break_glass        = "roles/owner"
  }

  # --- 7.3: Active vs Terminated logic ---
  users_list = try(local.users.users, [])

  active_users = [
    for u in local.users_list : u
    if lower(try(u.status, "active")) == "active"
  ]

  terminated_users = [
    for u in local.users_list : u
    if lower(try(u.status, "active")) != "active"
  ]

  active_users_by_email = {
    for u in local.active_users : lower(u.email) => u
  }

  terminated_users_by_email = {
    for u in local.terminated_users : lower(u.email) => u
  }

  # --- 7.4: Desired memberships per persona ---
  active_user_persona_pairs = [
    for email, u in local.active_users_by_email : {
      email   = email
      persona = try(u.persona, null)
    }
    if try(u.persona, null) != null
  ]

  desired_memberships_by_persona = {
    for p in keys(local.azure_persona_to_role) :
    p => sort([
      for pair in local.active_user_persona_pairs : pair.email
      if pair.persona == p
    ])
  }
}

module "azure_iam" {
  source = "../../modules/azure-iam"

  location            = var.location
  resource_group_name = var.resource_group_name
}

module "aws_iam" {
  source = "../../modules/aws-iam"

  count = var.enable_aws ? 1 : 0
  providers = {
    aws = aws.optional
  }
  name_prefix                  = var.aws_name_prefix
  max_session_duration_seconds = var.aws_max_session_duration_seconds

  persona_to_policy_arns = local.aws_persona_to_policy_arns
}

module "gcp_iam" {
  source = "../../modules/gcp-iam"
  count  = var.enable_gcp ? 1 : 0
  providers = {
    google = google.optional
  }
  project_id  = var.gcp_project_id
  name_prefix = var.gcp_name_prefix

  persona_to_role = local.gcp_persona_to_role

  persona_group_emails = {
    security_analyst   = "grp-iam-security-analyst@example.com"
    auditor            = "grp-iam-auditor@example.com"
    cloud_engineer     = "grp-iam-cloud-engineer@example.com"
    devsecops_engineer = "grp-iam-devsecops-engineer@example.com"
    break_glass        = "grp-iam-break-glass@example.com"
  }
}