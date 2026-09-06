output "cluster_name" {
  value = aws_ecs_cluster.analysis_mngr.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.analysis_mngr.arn
}

output "service_name" {
  value = aws_ecs_service.analysis_mngr.name
}

output "service_arn" {
  value = aws_ecs_service.analysis_mngr.id
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.analysis_mngr.arn
}

output "task_definition_family" {
  value = aws_ecs_task_definition.analysis_mngr.family
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.analysis_mngr.name
}
