output "file_system_id" {
  description = "ID of the S3 file system"
  value       = module.s3_files.file_system_id
}

output "function_name" {
  description = "Name of the Lambda function that mounts the file system at /mnt/s3data"
  value       = aws_lambda_function.processor.function_name
}

output "invoke_command" {
  description = "Command to invoke the function and print its response"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.processor.function_name} --region ${var.aws_region} response.json && cat response.json"
}
