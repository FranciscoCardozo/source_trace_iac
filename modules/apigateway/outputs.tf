output "invoker_api_id" {
  value = aws_api_gateway_rest_api.invoker.id
}

output "invoker_invoke_url" {
  value = aws_api_gateway_stage.invoker.invoke_url
}

output "invoker_execution_arn" {
  value = aws_api_gateway_rest_api.invoker.execution_arn
}

output "response_api_id" {
  value = aws_api_gateway_rest_api.response.id
}

output "response_invoke_url" {
  value = aws_api_gateway_stage.response.invoke_url
}

output "response_execution_arn" {
  value = aws_api_gateway_rest_api.response.execution_arn
}

output "stage_name" {
  value = aws_api_gateway_stage.invoker.stage_name
}
