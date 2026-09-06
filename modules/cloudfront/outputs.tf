output "web_ui_distribution_id" {
  value = aws_cloudfront_distribution.web_ui.id
}

output "web_ui_distribution_arn" {
  value = aws_cloudfront_distribution.web_ui.arn
}

output "web_ui_domain_name" {
  value = aws_cloudfront_distribution.web_ui.domain_name
}

output "results_distribution_id" {
  value = aws_cloudfront_distribution.results.id
}

output "results_domain_name" {
  value = aws_cloudfront_distribution.results.domain_name
}
