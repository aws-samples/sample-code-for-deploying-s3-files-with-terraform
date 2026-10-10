variable "aws_region" {
  description = "AWS Region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name passed to the module (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "ID of an existing VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of existing private subnets in at least two Availability Zones (one mount target per subnet)"
  type        = list(string)
}

variable "bucket_arn" {
  description = "ARN of an existing S3 general purpose bucket with versioning enabled"
  type        = string
}
