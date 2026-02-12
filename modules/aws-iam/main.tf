#5.1
data "aws_caller_identity" "current" {}

# v1 trust model: allow principals in THIS AWS account to assume these roles.
# Later (Phase 7/11), we’ll replace with federation (Okta/SAML/OIDC) patterns.
data "aws_iam_policy_document" "assume_role_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

# Create one role per persona
resource "aws_iam_role" "persona" {
  for_each = var.persona_to_policy_arns

  name                 = "${var.name_prefix}-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_trust.json
  max_session_duration = var.max_session_duration_seconds
  permissions_boundary = local.effective_permission_boundary_arn
  tags = {
    Project = "Multicloud IAM Automation using Terraform"
    Phase   = "5"
    Persona = each.key
  }
}

# Attach policies (flatten persona->policy list into unique attachments)
locals {
  persona_policy_pairs = flatten([
    for persona, arns in var.persona_to_policy_arns : [
      for arn in arns : {
        persona = persona
        arn     = arn
      }
    ]
  ])

  attachments = {
    for p in local.persona_policy_pairs :
    "${p.persona}::${p.arn}" => p
  }
}

resource "aws_iam_role_policy_attachment" "persona" {
  for_each = local.attachments

  role       = aws_iam_role.persona[each.value.persona].name
  policy_arn = each.value.arn

}
# Placeholder permission boundary (tighten later)
data "aws_iam_policy_document" "permission_boundary" {
  statement {
    sid       = "AllowAllActionsPlaceholder"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "permission_boundary" {
  count       = var.use_permission_boundary && var.permission_boundary_policy_arn == null ? 1 : 0
  name        = "${var.name_prefix}-permission-boundary"
  description = "Placeholder permission boundary for persona roles (tighten in later phases)"
  policy      = data.aws_iam_policy_document.permission_boundary.json
}

locals {
  effective_permission_boundary_arn = var.use_permission_boundary ? (
    var.permission_boundary_policy_arn != null ? var.permission_boundary_policy_arn : aws_iam_policy.permission_boundary[0].arn
  ) : null
}