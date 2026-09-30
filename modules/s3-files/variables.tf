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

variable "import_trigger" {
  description = "When S3 Files imports file data: ON_DIRECTORY_FIRST_ACCESS or ON_FILE_ACCESS"
  type        = string
  default     = "ON_DIRECTORY_FIRST_ACCESS"
  validation {
    condition     = contains(["ON_DIRECTORY_FIRST_ACCESS", "ON_FILE_ACCESS"], var.import_trigger)
    error_message = "import_trigger must be ON_DIRECTORY_FIRST_ACCESS or ON_FILE_ACCESS."
  }
}

variable "import_size_threshold" {
  description = "Import data only for files smaller than this many bytes (metadata is always imported). Default 128 KiB."
  type        = number
  default     = 131072
}

variable "expiration_days" {
  description = "Days without a read before file data is expired from the file system (1-365). Data remains in S3."
  type        = number
  default     = 30
  validation {
    condition     = var.expiration_days >= 1 && var.expiration_days <= 365
    error_message = "expiration_days must be between 1 and 365."
  }
}

variable "accept_bucket_warning" {
  description = "Acknowledge the warning S3 Files raises for buckets/prefixes with a very large number of objects (~12M)."
  type        = bool
  default     = false
}

variable "access_points" {
  description = "Map of access points to create for scoped access"
  type = map(object({
    path = string
    posix_user = optional(object({
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
