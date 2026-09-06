# ------------------------------------------------------------------
# SOURCE_TRACE_RESPONSE_API - consulta estado/resultados del analisis.
#
# Definido enteramente por definitions/Api_source_trace_response.json:
#   GET /V1/product/status/analysis  (headers x-job-id, x-process)
#   OPTIONS  (CORS preflight, MOCK)
# La ruta apunta a SOURCE_TRACE_RESPONSE_FUNCTION via $${lambda_arn}.
# ------------------------------------------------------------------

locals {
  response_body = templatefile("${path.module}/definitions/Api_source_trace_response.json", {
    lambda_arn = var.response_lambda_arn
  })
}

resource "aws_api_gateway_rest_api" "response" {
  name        = "${var.name}_response_api"
  description = "Source Trace - API response (consulta estado/resultados), definido via OAS"
  body        = local.response_body

  put_rest_api_mode = "overwrite"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.tags
}

resource "aws_lambda_permission" "response" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.response_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.response.execution_arn}/*/*/*"
}

resource "aws_api_gateway_deployment" "response" {
  rest_api_id = aws_api_gateway_rest_api.response.id

  triggers = {
    redeployment = sha1(local.response_body)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "response_access" {
  name              = "/aws/apigateway/${var.name}_response_api"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_api_gateway_stage" "response" {
  rest_api_id   = aws_api_gateway_rest_api.response.id
  deployment_id = aws_api_gateway_deployment.response.id
  stage_name    = var.stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.response_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.tags

  depends_on = [aws_api_gateway_account.this]
}
