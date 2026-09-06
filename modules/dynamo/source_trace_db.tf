# ------------------------------------------------------------------
# SOURCE_TRACE_DB: resultados del analysis manager
# PK = job id, SK = tipo de registro. GSI por estado para consultas
# de la Lambda de resultados.
# ------------------------------------------------------------------

resource "aws_dynamodb_table" "source_trace_db" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "status-createdAt-index"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Name        = var.table_name
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
