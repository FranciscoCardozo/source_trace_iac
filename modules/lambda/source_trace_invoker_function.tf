# ------------------------------------------------------------------
# SOURCE_TRACE_INVOKER_FUNCTION
# API Gateway -> Lambda -> StartExecution del Step Functions workflow.
# StartExecution es asincrono: la Lambda responde 202 al instante, el
# front no espera al analisis.
# ------------------------------------------------------------------

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  invoker_name = "${var.name}_invoker_function"
}

data "archive_file" "invoker" {
  type        = "zip"
  source_dir  = "${path.module}/src/invoker"
  output_path = "${path.module}/build/invoker.zip"
}

resource "aws_iam_role" "invoker" {
  name = "${local.invoker_name}_role"
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

resource "aws_iam_role_policy_attachment" "invoker_basic" {
  role       = aws_iam_role.invoker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "invoker" {
  name = "${local.invoker_name}_policy"
  role = aws_iam_role.invoker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = var.state_machine_arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.dynamodb_table_arn
      },
      {
        # Firma URLs prefirmadas para que el front suba el codigo fuente.
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.upload_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "invoker" {
  name              = "/aws/lambda/${local.invoker_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_lambda_function" "invoker" {
  function_name    = local.invoker_name
  role             = aws_iam_role.invoker.arn
  runtime          = var.runtime
  handler          = "index.handler"
  filename         = data.archive_file.invoker.output_path
  source_code_hash = data.archive_file.invoker.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ANALYSIS_STATE_MACHINE_ARN = var.state_machine_arn
      DYNAMODB_TABLE             = var.dynamodb_table_name
      UPLOAD_BUCKET              = var.upload_bucket_id
      DEBUG                      = "invoker:*"
    }
  }

  lifecycle {
    # El codigo lo despliega el repo FranciscoCardozo/source_trace_invoker_function
    # via GitHub Actions (aws lambda update-function-code). Terraform solo deja el
    # stub de arranque y no pisa lo que sube el CI.
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_cloudwatch_log_group.invoker]
  tags       = local.tags
}
