output "ecr_repository_name" {
  description = "MODEL_LOADER_ECR_REPOSITORY"
  value       = aws_ecr_repository.model_loader.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.model_loader.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.model_loader.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.model_loader.name
}
