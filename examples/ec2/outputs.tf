output "file_system_id" {
  description = "ID of the S3 file system"
  value       = module.s3_files.file_system_id
}

output "instance_id" {
  description = "ID of the EC2 instance that mounts the file system at /mnt/s3files"
  value       = aws_instance.app.id
}

output "connect_command" {
  description = "Command to open a Session Manager shell on the instance"
  value       = "aws ssm start-session --target ${aws_instance.app.id} --region ${var.aws_region}"
}
