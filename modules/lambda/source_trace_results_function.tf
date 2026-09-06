# ------------------------------------------------------------------
# SOURCE_TRACE_RESULTS_FUNCTION
# API Gateway -> Lambda -> DynamoDB + bucket de resultados
# ------------------------------------------------------------------

locals {
  results_name = "${var.name}_results_function"
}

data "archive_file" "results" {
  type        = "zip"
  source_dir  = "${path.module}/src/results"
  output_path = "${path.module}/build/results.zip"
}

resource "aws_iam_role" "results" {
  name = "${local.results_name}_role"
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

resource "aws_iam_role_policy_attachment" "results_basic" {
  role       = aws_iam_role.results.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "results" {
  name = "${local.results_name}_policy"
  role = aws_iam_role.results.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [var.results_bucket_arn, "${var.results_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "results" {
  name              = "/aws/lambda/${local.results_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_lambda_function" "results" {
  function_name    = local.results_name
  role             = aws_iam_role.results.arn
  runtime          = var.runtime
  handler          = "index.handler"
  filename         = data.archive_file.results.output_path
  source_code_hash = data.archive_file.results.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE     = var.dynamodb_table_name
      RESULTS_BUCKET     = var.results_bucket_id
      RESULTS_CDN_DOMAIN = var.results_cdn_domain
    }
  }

  lifecycle {
    # El codigo lo despliega el repo FranciscoCardozo/source_trace_response_function
    # via GitHub Actions (aws lambda update-function-code). Terraform solo deja el
    # stub de arranque y no pisa lo que sube el CI.
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_cloudwatch_log_group.results]
  tags       = local.tags
}
