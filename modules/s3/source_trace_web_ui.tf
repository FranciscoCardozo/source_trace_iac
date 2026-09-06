# ------------------------------------------------------------------
# Bucket del Web UI (SPA estatica servida por SOURCE_TRACE_CLOUDFRONT)
# Privado: solo accesible via CloudFront + OAC (policy en el modulo cloudfront)
# ------------------------------------------------------------------

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  # Los nombres de bucket S3 no admiten "_"
  bucket_prefix = replace(var.name, "_", "-")
}

resource "aws_s3_bucket" "web_ui" {
  bucket = "${local.bucket_prefix}-web-ui-${var.account_id}"
  tags   = merge(local.tags, { Name = "${var.name}_web_ui" })
}

resource "aws_s3_bucket_versioning" "web_ui" {
  bucket = aws_s3_bucket.web_ui.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "web_ui" {
  bucket                  = aws_s3_bucket.web_ui.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web_ui" {
  bucket = aws_s3_bucket.web_ui.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
