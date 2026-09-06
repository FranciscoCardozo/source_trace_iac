output "invoker_function_name" {
  value = aws_lambda_function.invoker.function_name
}

output "invoker_function_arn" {
  value = aws_lambda_function.invoker.arn
}

output "invoker_invoke_arn" {
  value = aws_lambda_function.invoker.invoke_arn
}

output "invoker_log_group_name" {
  value = aws_cloudwatch_log_group.invoker.name
}

output "results_function_name" {
  value = aws_lambda_function.results.function_name
}

output "results_function_arn" {
  value = aws_lambda_function.results.arn
}

output "results_invoke_arn" {
  value = aws_lambda_function.results.invoke_arn
}

output "results_log_group_name" {
  value = aws_cloudwatch_log_group.results.name
}
