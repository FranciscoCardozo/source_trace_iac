# ------------------------------------------------------------------
# Bucket de subida de codigo fuente.
# El front pide a SOURCE_TRACE_API (Lambda invoker) una URL prefirmada y
# sube el archivo directo a S3 (PUT). El ECS analysis manager lo lee para
# analizarlo con Qwen.
# Privado. Los objetos expiran solos (no hace falta guardarlos para siempre).
# ------------------------------------------------------------------

resource "aws_s3_bucket" "upload" {
  bucket = "${local.bucket_prefix}-upload-${var.account_id}"
  tags   = merge(local.tags, { Name = "${var.name}_upload" })
}

resource "aws_s3_bucket_versioning" "upload" {
  bucket = aws_s3_bucket.upload.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "upload" {
  bucket                  = aws_s3_bucket.upload.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "upload" {
  bucket = aws_s3_bucket.upload.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# El navegador hace PUT contra la URL prefirmada: hay que habilitar CORS
# y exponer el header ETag para que el cliente confirme la subida.
resource "aws_s3_bucket_cors_configuration" "upload" {
  bucket = aws_s3_bucket.upload.id
  cors_rule {
    allowed_methods = ["PUT", "POST", "GET", "HEAD"]
    allowed_origins = var.upload_allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "upload" {
  bucket = aws_s3_bucket.upload.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"

    filter {}

    expiration {
      days = var.upload_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
