output "file_system_id" {
  description = "ID of the S3 file system"
  value       = module.s3_files.file_system_id
}

output "cluster_name" {
  description = "Name of the ECS cluster running the task"
  value       = aws_ecs_cluster.main.name
}

output "log_group_name" {
  description = "CloudWatch Logs group with the container output"
  value       = aws_cloudwatch_log_group.app.name
}
