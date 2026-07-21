terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.40.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "optima-desktop"

  default_tags {
    tags = {
      Project     = "s3-files-blog"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# VPC Data Sources (using existing VPC)
# ------------------------------------------------------------------------------

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

# ------------------------------------------------------------------------------
# S3 Bucket (create for testing)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "test" {
  bucket_prefix = "s3files-blog-dev-"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "test" {
  bucket = aws_s3_bucket.test.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# IAM Role for S3 Files Service
# ------------------------------------------------------------------------------

resource "aws_iam_role" "s3files_service" {
  name_prefix = "s3files-dev-service-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "elasticfilesystem.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# S3 permissions for sync
resource "aws_iam_role_policy" "s3files_s3_access" {
  name = "s3-access"
  role = aws_iam_role.s3files_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BucketAccess"
        Effect = "Allow"
        Action = ["s3:ListBucket*"]
        Resource = [aws_s3_bucket.test.arn]
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:GetObject*",
          "s3:List*",
          "s3:PutObject*"
        ]
        Resource = ["${aws_s3_bucket.test.arn}/*"]
      }
    ]
  })
}

# EventBridge permissions for change detection
resource "aws_iam_role_policy" "s3files_eventbridge" {
  name = "eventbridge-access"
  role = aws_iam_role.s3files_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgeManage"
        Effect = "Allow"
        Action = [
          "events:DeleteRule",
          "events:DisableRule",
          "events:EnableRule",
          "events:PutRule",
          "events:PutTargets",
          "events:RemoveTargets"
        ]
        Resource = ["arn:aws:events:${var.aws_region}:*:rule/DO-NOT-DELETE-S3-Files*"]
      },
      {
        Sid      = "EventBridgeList"
        Effect   = "Allow"
        Action   = ["events:ListRules"]
        Resource = ["*"]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Compute Security Group
# ------------------------------------------------------------------------------

resource "aws_security_group" "compute" {
  name_prefix = "s3files-dev-compute-"
  description = "Security group for compute resources accessing S3 Files"
  vpc_id      = var.vpc_id

  tags = {
    Name = "s3files-dev-compute-sg"
  }
}

# Egress rule added after module creates the FS security group
resource "aws_vpc_security_group_egress_rule" "compute_to_fs" {
  security_group_id            = aws_security_group.compute.id
  referenced_security_group_id = module.s3_files.security_group_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS to S3 Files mount targets"
}

# ------------------------------------------------------------------------------
# S3 Files Module
# ------------------------------------------------------------------------------

module "s3_files" {
  source = "../../modules/s3-files"

  depends_on = [aws_s3_bucket_versioning.test]

  environment = "dev"
  bucket_arn  = aws_s3_bucket.test.arn
  role_arn    = aws_iam_role.s3files_service.arn
  vpc_id      = var.vpc_id
  subnet_ids  = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : slice(data.aws_subnets.private.ids, 0, min(2, length(data.aws_subnets.private.ids)))

  compute_security_group_ids = [aws_security_group.compute.id]

  # Required for Lambda IAM policy condition constraints
  vpc_arn             = data.aws_vpc.selected.arn
  private_subnet_arns = [for s in var.private_subnet_ids : "arn:aws:ec2:${var.aws_region}:*:subnet/${s}"]

  # Dev uses SSE-S3 (no KMS key)
  kms_key_arn = null

  access_points = {
    app = {
      path = "/app-data"
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory_creation_info = null
    }
  }

  tags = {
    CostCenter = "engineering"
    Test       = "s3-files-blog"
  }
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "file_system_id" {
  value = module.s3_files.file_system_id
}

output "bucket_name" {
  value = aws_s3_bucket.test.id
}

output "mount_command" {
  value = module.s3_files.mount_helper_command
}

output "security_group_id" {
  value = module.s3_files.security_group_id
}
