# ------------------------------------------------------------------
# SOURCE_TRACE_RESULTS_CLOUDFRONT -> bucket de resultados (imagenes/artefactos)
# ------------------------------------------------------------------

locals {
  results_origin_id = "${var.name}-results-s3"
}

resource "aws_cloudfront_origin_access_control" "results" {
  name                              = "${var.name}-results-oac"
  description                       = "OAC para el bucket de resultados"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "results" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name} results assets"
  price_class     = var.price_class

  origin {
    domain_name              = var.results_bucket_regional_domain_name
    origin_id                = local.results_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.results.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.results_origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # CachingOptimized (managed)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    # CORS-S3Origin (managed) para servir imagenes a la SPA
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.tags, { Name = "${var.name}_results_cloudfront" })
}

# --- Policy del bucket de resultados: solo esta distribucion -------
data "aws_iam_policy_document" "results" {
  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    actions   = ["s3:GetObject"]
    resources = ["${var.results_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.results.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "results" {
  bucket = var.results_bucket_id
  policy = data.aws_iam_policy_document.results.json
}
