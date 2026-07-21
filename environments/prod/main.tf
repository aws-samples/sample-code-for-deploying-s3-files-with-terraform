terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.40.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "s3-files/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "s3-files-blog"
      Environment = "prod"
    }
  }
}

# Customer-managed KMS key for production encryption
resource "aws_kms_key" "s3files" {
  description             = "KMS key for S3 Files encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "s3files-prod-key"
  }
}

resource "aws_kms_alias" "s3files" {
  name          = "alias/s3files-prod"
  target_key_id = aws_kms_key.s3files.key_id
}

# KMS key policy granting S3 Files service principal access
resource "aws_kms_key_policy" "s3files" {
  key_id = aws_kms_key.s3files.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowS3FilesService"
        Effect = "Allow"
        Principal = {
          Service = "s3files.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3files.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

module "s3_files" {
  source = "../../modules/s3-files"

  environment = "prod"
  bucket_name = var.bucket_name
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  compute_security_group_ids = var.compute_security_group_ids

  # Production uses customer-managed KMS key
  kms_key_arn = aws_kms_key.s3files.arn

  enable_sync_to_s3   = true
  enable_sync_from_s3 = true

  allowed_principal_arns = var.allowed_principal_arns

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
    analytics = {
      path = "/analytics"
      posix_user = {
        uid = 2000
        gid = 2000
      }
      root_directory_creation_info = {
        owner_uid   = 2000
        owner_gid   = 2000
        permissions = "750"
      }
    }
  }

  tags = {
    CostCenter  = "platform"
    Compliance  = "required"
    DataClass   = "confidential"
  }
}

# Compute security group for prod instances
resource "aws_security_group" "compute" {
  name_prefix = "s3files-prod-compute-"
  description = "Security group for compute resources accessing S3 Files"
  vpc_id      = var.vpc_id

  egress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.s3_files.security_group_id]
    description     = "NFS to S3 Files mount targets"
  }

  tags = {
    Name = "s3files-prod-compute-sg"
  }
}
