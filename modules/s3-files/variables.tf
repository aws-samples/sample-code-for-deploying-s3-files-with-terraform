variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "bucket_arn" {
  description = "ARN of the existing S3 general purpose bucket to expose as a file system"
  type        = string
}

variable "role_arn" {
  description = "ARN of the IAM role that grants S3 Files permission to sync data between the file system and S3 bucket. Must trust elasticfilesystem.amazonaws.com."
  type        = string
}

variable "prefix" {
  description = "Optional prefix within the S3 bucket to scope file system access. If not specified, the entire bucket is accessible."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID where mount targets will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for mount targets (one per AZ for HA)"
  type        = list(string)
}

variable "compute_security_group_ids" {
  description = "Security group IDs of compute resources that will mount the file system"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption. If null, SSE-S3 is used"
  type        = string
  default     = null
}

variable "enable_sync_to_s3" {
  description = "Enable automatic synchronization from file system to S3"
  type        = bool
  default     = true
}

variable "enable_sync_from_s3" {
  description = "Enable automatic synchronization from S3 to file system"
  type        = bool
  default     = true
}

variable "access_points" {
  description = "Map of access points to create for scoped access"
  type = map(object({
    path        = string
    posix_user  = optional(object({
      uid = number
      gid = number
    }))
    root_directory_creation_info = optional(object({
      owner_uid   = number
      owner_gid   = number
      permissions = string
    }))
  }))
  default = {}
}

variable "allowed_principal_arns" {
  description = "List of IAM principal ARNs allowed to access the file system"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_arn" {
  description = "ARN of the VPC (used to constrain Lambda ENI creation to a specific VPC)"
  type        = string
  default     = null
}

variable "private_subnet_arns" {
  description = "ARNs of the private subnets (used to constrain Lambda ENI creation)"
  type        = list(string)
  default     = []
}
