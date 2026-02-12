#7.1 
/*locals {
  personas = yamldecode(file("${path.root}/../../identities/personas.yaml"))
  users    = yamldecode(file("${path.root}/../../identities/users.yaml"))
}*/
#7.2 
locals {
  # --- YAML loaded in Phase 7.1 ---
  personas = yamldecode(file("${path.root}/../../identities/personas.yaml"))
  users    = yamldecode(file("${path.root}/../../identities/users.yaml"))

  # --- 7.2: Persona → Cloud mappings (v1) ---
  # Keep these simple now; we’ll refine to least-privilege in Phase 9.
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
}

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

#6.2
module "gcp_iam" {
  source = "../../modules/gcp-iam"

  project_id  = var.gcp_project_id
  name_prefix = var.gcp_name_prefix

  persona_to_role = {
    security_analyst   = "roles/viewer"
    auditor            = "roles/viewer"
    cloud_engineer     = "roles/editor"
    devsecops_engineer = "roles/editor"
    break_glass        = "roles/owner"
  }

  # Use placeholders for code-only until you create real Google Groups
  persona_group_emails = {
    security_analyst   = "grp-iam-security-analyst@example.com"
    auditor            = "grp-iam-auditor@example.com"
    cloud_engineer     = "grp-iam-cloud-engineer@example.com"
    devsecops_engineer = "grp-iam-devsecops-engineer@example.com"
    break_glass        = "grp-iam-break-glass@example.com"
  }
}