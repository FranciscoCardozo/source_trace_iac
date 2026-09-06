output "state_machine_arn" {
  value = aws_sfn_state_machine.analysis.arn
}

output "state_machine_name" {
  value = aws_sfn_state_machine.analysis.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.sfn.name
}

output "role_arn" {
  value = aws_iam_role.sfn.arn
}
