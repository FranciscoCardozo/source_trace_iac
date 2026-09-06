output "role_arn" {
  description = "secrets.AWS_DEPLOY_ROLE_ARN en los workflows de GitHub Actions"
  value       = aws_iam_role.deploy.arn
}

output "role_name" {
  value = aws_iam_role.deploy.name
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "lambda_deploy_role_arns" {
  description = "secrets.AWS_DEPLOY_ROLE_ARN por repo de Lambda (clave = alias)"
  value       = { for k, r in aws_iam_role.lambda_deploy : k => r.arn }
}

output "frontend_deploy_role_arns" {
  description = "secrets.AWS_DEPLOY_ROLE_ARN por repo de frontend (clave = alias)"
  value       = { for k, r in aws_iam_role.frontend_deploy : k => r.arn }
}
