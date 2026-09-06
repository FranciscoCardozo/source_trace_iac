# ------------------------------------------------------------------
# Scale-down on-demand del servicio qwen-inference.
#
# El scale-UP lo hace el Step Functions (estado EnsureModelUp: updateService
# desiredCount=1 + espera a que llama.cpp cargue). Este modulo solo apaga:
# un Lambda que corre cada check_interval_minutes y pone desiredCount=0 si
# no hay ejecuciones del pipeline en curso ni recientes.
# ------------------------------------------------------------------

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  fn_name           = "${var.name}_qwen_scale_down"
  model_service_arn = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster_name}/${var.model_service_name}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "archive_file" "scale_down" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/scale_down.zip"
}

resource "aws_iam_role" "scale_down" {
  name = "${local.fn_name}_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.scale_down.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "scale_down" {
  name = "${local.fn_name}_policy"
  role = aws_iam_role.scale_down.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListExecutions"
        Effect   = "Allow"
        Action   = ["states:ListExecutions"]
        Resource = var.state_machine_arn
      },
      {
        Sid      = "ReadService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices"]
        Resource = "*"
      },
      {
        Sid      = "ScaleService"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = local.model_service_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "scale_down" {
  name              = "/aws/lambda/${local.fn_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_lambda_function" "scale_down" {
  function_name    = local.fn_name
  role             = aws_iam_role.scale_down.arn
  runtime          = "python3.12"
  handler          = "scale_down.handler"
  filename         = data.archive_file.scale_down.output_path
  source_code_hash = data.archive_file.scale_down.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      STATE_MACHINE_ARN = var.state_machine_arn
      ECS_CLUSTER       = var.ecs_cluster_arn
      MODEL_SERVICE     = var.model_service_name
      IDLE_MINUTES      = tostring(var.idle_minutes)
    }
  }

  depends_on = [aws_cloudwatch_log_group.scale_down]
  tags       = local.tags
}

resource "aws_cloudwatch_event_rule" "tick" {
  name                = "${local.fn_name}_tick"
  description         = "Chequeo de inactividad del servicio qwen-inference"
  schedule_expression = "rate(${var.check_interval_minutes} minutes)"
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "tick" {
  rule = aws_cloudwatch_event_rule.tick.name
  arn  = aws_lambda_function.scale_down.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_down.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.tick.arn
}
