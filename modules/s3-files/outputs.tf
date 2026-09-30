output "file_system_id" {
  description = "ID of the S3 file system (used with mount helper: mount -t s3files fs-xxx:/ /mnt/s3files)"
  value       = aws_s3files_file_system.this.id
}

output "file_system_arn" {
  description = "ARN of the S3 file system (used in ECS s3filesVolumeConfiguration)"
  value       = aws_s3files_file_system.this.arn
}

output "mount_target_ids" {
  description = "Map of subnet ID to mount target ID"
  value       = { for i, mt in aws_s3files_mount_target.this : var.subnet_ids[i] => mt.id }
}

output "mount_target_ips" {
  description = "Map of subnet ID to mount target IPv4 address"
  value       = { for i, mt in aws_s3files_mount_target.this : var.subnet_ids[i] => mt.ipv4_address }
}

output "security_group_id" {
  description = "Security group ID for the file system mount targets"
  value       = aws_security_group.file_system.id
}

output "access_point_ids" {
  description = "Map of access point name to access point ID"
  value       = { for k, v in aws_s3files_access_point.this : k => v.id }
}

output "access_point_arns" {
  description = "Map of access point name to access point ARN (used for Lambda and ECS)"
  value       = { for k, v in aws_s3files_access_point.this : k => v.arn }
}

output "ec2_iam_policy_arn" {
  description = "IAM policy ARN for EC2 instances to mount the file system"
  value       = aws_iam_policy.ec2_s3files.arn
}

output "ecs_iam_policy_arn" {
  description = "IAM policy ARN for ECS tasks to mount the file system"
  value       = aws_iam_policy.ecs_s3files.arn
}

output "lambda_iam_policy_arn" {
  description = "IAM policy ARN for Lambda functions to mount the file system"
  value       = aws_iam_policy.lambda_s3files.arn
}

output "mount_helper_command" {
  description = "Mount command using amazon-efs-utils mount helper (recommended for EC2)"
  value       = "sudo mount -t s3files ${aws_s3files_file_system.this.id}:/ /mnt/s3files"
}
