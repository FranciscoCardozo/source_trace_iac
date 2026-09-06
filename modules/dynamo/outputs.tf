output "table_name" {
  value = aws_dynamodb_table.source_trace_db.name
}

output "table_arn" {
  value = aws_dynamodb_table.source_trace_db.arn
}

output "table_gsi_arns" {
  value = ["${aws_dynamodb_table.source_trace_db.arn}/index/*"]
}
