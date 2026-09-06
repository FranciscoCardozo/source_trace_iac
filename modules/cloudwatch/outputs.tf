output "dashboard_name" {
  value = aws_cloudwatch_dashboard.analysis_mngr.dashboard_name
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.analysis_mngr.dashboard_name}"
}

output "alarms_topic_arn" {
  value = aws_sns_topic.alarms.arn
}
