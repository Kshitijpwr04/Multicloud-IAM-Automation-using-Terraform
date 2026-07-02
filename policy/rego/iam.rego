package iam.guardrails

# ---- Rule: deny dangerous built-in roles in Azure ----
deny[msg] {
  input.resource_type == "azurerm_role_assignment"
  role := lower(input.values.role_definition_name)
  role == "owner"
  not input.meta.allow_owner
  msg := sprintf("Azure role 'Owner' is not allowed (use break_glass process). Resource: %s", [input.address])
}

# ---- Rule: deny AWS AdministratorAccess unless explicitly allowed ----
deny[msg] {
  input.resource_type == "aws_iam_role_policy_attachment"
  arn := input.values.policy_arn
  arn == "arn:aws:iam::aws:policy/AdministratorAccess"
  not input.meta.allow_admin
  msg := sprintf("AWS AdministratorAccess is not allowed (use break_glass process). Resource: %s", [input.address])
}

# ---- Rule: block break_glass in joiner/mover requests (defense-in-depth) ----
deny[msg] {
  input.kind == "access_request"
  input.request_type == "joiner"
  input.user.persona == "break_glass"
  msg := "Joiner cannot request break_glass persona"
}

deny[msg] {
  input.kind == "access_request"
  input.request_type == "mover"
  input.user.new_persona == "break_glass"
  msg := "Mover cannot assign break_glass persona"
}