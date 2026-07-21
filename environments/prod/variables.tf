variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name to expose as a file system"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for mount targets (one per AZ)"
  type        = list(string)
}

variable "compute_security_group_ids" {
  description = "Security group IDs for compute resources"
  type        = list(string)
}

variable "allowed_principal_arns" {
  description = "IAM principal ARNs allowed to access the file system"
  type        = list(string)
}
