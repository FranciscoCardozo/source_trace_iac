# ------------------------------------------------------------------
# Recursos compartidos por todos los APIs REST del modulo.
#
# El rol y aws_api_gateway_account configuran el ARN que API Gateway usa
# para escribir en CloudWatch Logs. Es un ajuste GLOBAL por cuenta/region
# (uno solo), por eso vive aca y no en el archivo de cada API.
# ------------------------------------------------------------------

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "cloudwatch" {
  name = "${var.name}_apigw_cloudwatch_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}
