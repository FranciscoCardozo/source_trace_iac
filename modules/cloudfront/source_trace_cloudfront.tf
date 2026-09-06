# ------------------------------------------------------------------
# SOURCE_TRACE_CLOUDFRONT -> bucket del Web UI (SPA)
# ------------------------------------------------------------------

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  web_ui_origin_id = "${var.name}-web-ui-s3"
}

resource "aws_cloudfront_origin_access_control" "web_ui" {
  name                              = "${var.name}-web-ui-oac"
  description                       = "OAC para el bucket del web UI"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "web_ui" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name} web UI"
  default_root_object = "index.html"
  price_class         = var.price_class

  origin {
    domain_name              = var.web_ui_bucket_regional_domain_name
    origin_id                = local.web_ui_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.web_ui.id
    # El CI publica en s3://<bucket>/app/, CloudFront sirve desde ese prefijo:
    # "/" -> app/index.html, "/assets/x" -> app/assets/x.
    origin_path = var.web_ui_origin_path
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.web_ui_origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # CachingOptimized (managed)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # SPA: rutas del cliente -> index.html
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.tags, { Name = "${var.name}_cloudfront" })
}

# --- Policy del bucket web UI: solo esta distribucion ---------------
data "aws_iam_policy_document" "web_ui" {
  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    actions   = ["s3:GetObject"]
    resources = ["${var.web_ui_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.web_ui.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web_ui" {
  bucket = var.web_ui_bucket_id
  policy = data.aws_iam_policy_document.web_ui.json
}
