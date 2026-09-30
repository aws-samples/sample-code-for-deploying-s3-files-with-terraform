terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.53.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "s3-files-blog"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------------------------
# VPC (self-contained — no external dependencies)
# ------------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "s3files-dev-vpc"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "s3files-dev-private-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# ------------------------------------------------------------------------------
# S3 Bucket (created for testing)
# ------------------------------------------------------------------------------

resource "random_id" "bucket" {
  byte_length = 8
}

resource "aws_s3_bucket" "test" {
  bucket        = "s3files-blog-dev-${random_id.bucket.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "test" {
  bucket = aws_s3_bucket.test.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# IAM Role for S3 Files Service (sync and change detection)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "s3files_service" {
  name_prefix = "s3files-dev-service-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "elasticfilesystem.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:s3files:${var.aws_region}:${data.aws_caller_identity.current.account_id}:file-system/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "s3files_s3_access" {
  name = "s3-access"
  role = aws_iam_role.s3files_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BucketAccess"
        Effect   = "Allow"
        Action   = ["s3:ListBucket*"]
        Resource = [aws_s3_bucket.test.arn]
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject*",
          "s3:GetObject*",
          "s3:List*",
          "s3:PutObject*"
        ]
        Resource = ["${aws_s3_bucket.test.arn}/*"]
      }
    ]
  })
}

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
        Resource = ["arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/DO-NOT-DELETE-S3-Files*"]
        Condition = {
          StringEquals = { "events:ManagedBy" = "elasticfilesystem.amazonaws.com" }
        }
      },
      {
        Sid    = "EventBridgeRead"
        Effect = "Allow"
        Action = [
          "events:DescribeRule",
          "events:ListRuleNamesByTarget",
          "events:ListRules",
          "events:ListTargetsByRule"
        ]
        Resource = ["arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/*"]
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
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "s3files-dev-compute-sg"
  }
}

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

  depends_on = [
    aws_s3_bucket_versioning.test,
    aws_iam_role_policy.s3files_s3_access,
    aws_iam_role_policy.s3files_eventbridge,
  ]

  environment = "dev"
  bucket_arn  = aws_s3_bucket.test.arn
  role_arn    = aws_iam_role.s3files_service.arn
  vpc_id      = aws_vpc.this.id
  subnet_ids  = aws_subnet.private[*].id

  compute_security_group_ids = [aws_security_group.compute.id]


  # Dev uses SSE-S3 (no KMS key)
  kms_key_arn = null

  access_points = {
    app = {
      path = "/app-data"
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory_creation_info = {
        owner_uid   = 1000
        owner_gid   = 1000
        permissions = "755"
      }
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

output "vpc_id" {
  value = aws_vpc.this.id
}
