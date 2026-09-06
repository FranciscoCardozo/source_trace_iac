# ------------------------------------------------------------------
# Bucket de resultados (imagenes / artefactos que genera el ECS)
# Lectura publica via SOURCE_TRACE_RESULTS_CLOUDFRONT (policy en modulo cloudfront)
# Escritura: task role del ECS analysis manager
# ------------------------------------------------------------------

resource "aws_s3_bucket" "results" {
  bucket = "${local.bucket_prefix}-results-${var.account_id}"
  tags   = merge(local.tags, { Name = "${var.name}_results" })
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "results" {
  bucket = aws_s3_bucket.results.id
  cors_rule {
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }
}
