output "web_ui_bucket_id" {
  value = aws_s3_bucket.web_ui.id
}

output "web_ui_bucket_arn" {
  value = aws_s3_bucket.web_ui.arn
}

output "web_ui_bucket_regional_domain_name" {
  value = aws_s3_bucket.web_ui.bucket_regional_domain_name
}

output "results_bucket_id" {
  value = aws_s3_bucket.results.id
}

output "results_bucket_arn" {
  value = aws_s3_bucket.results.arn
}

output "results_bucket_regional_domain_name" {
  value = aws_s3_bucket.results.bucket_regional_domain_name
}

output "upload_bucket_id" {
  value = aws_s3_bucket.upload.id
}

output "upload_bucket_arn" {
  value = aws_s3_bucket.upload.arn
}

output "upload_bucket_regional_domain_name" {
  value = aws_s3_bucket.upload.bucket_regional_domain_name
}
