# ------------------------------------------------------------------
# SOURCE_TRACE_API (invoker) - dispara el analisis.
#
# Definido enteramente por definitions/Api_source_trace.json. Todas las
# rutas apuntan a SOURCE_TRACE_INVOKER_FUNCTION via $${lambda_arn}.
# `put_rest_api_mode = "overwrite"` deja el API exactamente como el OAS en
# cada apply (si se borra un path del archivo, se borra del API).
# ------------------------------------------------------------------

locals {
  invoker_body = templatefile("${path.module}/definitions/Api_source_trace.json", {
    lambda_arn = var.invoker_lambda_arn
  })
}

resource "aws_api_gateway_rest_api" "invoker" {
  name        = "${var.name}_api"
  description = "Source Trace - API invoker (dispara el analisis), definido via OAS"
  body        = local.invoker_body

  put_rest_api_mode = "overwrite"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.tags
}

# El OAS puede tener cualquier cantidad de paths/metodos, todos contra la
# misma Lambda: el permiso cubre todo el API (stage/metodo/recurso).
resource "aws_lambda_permission" "invoker" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.invoker_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.invoker.execution_arn}/*/*/*"
}

resource "aws_api_gateway_deployment" "invoker" {
  rest_api_id = aws_api_gateway_rest_api.invoker.id

  triggers = {
    redeployment = sha1(local.invoker_body)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "invoker_access" {
  name              = "/aws/apigateway/${var.name}_api"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_api_gateway_stage" "invoker" {
  rest_api_id   = aws_api_gateway_rest_api.invoker.id
  deployment_id = aws_api_gateway_deployment.invoker.id
  stage_name    = var.stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.invoker_access.arn
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

# Renombrado de recursos (antes el modulo tenia un solo API con sufijo .this).
moved {
  from = aws_api_gateway_rest_api.this
  to   = aws_api_gateway_rest_api.invoker
}
moved {
  from = aws_lambda_permission.lambda
  to   = aws_lambda_permission.invoker
}
moved {
  from = aws_api_gateway_deployment.this
  to   = aws_api_gateway_deployment.invoker
}
moved {
  from = aws_cloudwatch_log_group.access
  to   = aws_cloudwatch_log_group.invoker_access
}
moved {
  from = aws_api_gateway_stage.this
  to   = aws_api_gateway_stage.invoker
}
