# Phase 2 stub
/*output "aws_module_ready" {
  value = true
}*/
#5.1
output "persona_role_arns" {
  value = { for k, r in aws_iam_role.persona : k => r.arn }
}