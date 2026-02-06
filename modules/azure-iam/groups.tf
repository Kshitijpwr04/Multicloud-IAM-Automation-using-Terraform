# Entra ID (Microsoft Graph) groups for persona-based access

locals {
  persona_groups = {
    security_analyst   = "grp-iam-security-analyst"
    auditor            = "grp-iam-auditor"
    cloud_engineer     = "grp-iam-cloud-engineer"
    devsecops_engineer = "grp-iam-devsecops-engineer"
    break_glass        = "grp-iam-break-glass"
  }
}

resource "msgraph_resource" "persona_group" {
  for_each = local.persona_groups

  url = "groups"

  body = {
    displayName     = each.value
    mailEnabled     = false
    # must be unique; keep it simple + deterministic
    mailNickname    = replace(each.value, "-", "")
    securityEnabled = true
  }
}
