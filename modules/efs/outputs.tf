output "file_system_id" {
  value = aws_efs_file_system.repo.id
}

output "file_system_arn" {
  value = aws_efs_file_system.repo.arn
}

output "access_point_id" {
  value = aws_efs_access_point.repo_rw.id
}

output "access_point_arn" {
  value = aws_efs_access_point.repo_rw.arn
}

output "security_group_id" {
  value = aws_security_group.efs.id
}
