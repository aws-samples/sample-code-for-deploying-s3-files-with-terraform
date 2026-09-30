terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.53.0"
    }
  }
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "s3files-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "s3-files"
  })
}

# ------------------------------------------------------------------------------
# S3 File System
# ------------------------------------------------------------------------------

resource "aws_s3files_file_system" "this" {
  bucket   = var.bucket_arn
  role_arn = var.role_arn

  kms_key_id            = var.kms_key_arn
  prefix                = var.prefix
  accept_bucket_warning = var.accept_bucket_warning

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${replace(var.bucket_arn, "/.*::/", "")}"
  })
}

# ------------------------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------------------------

resource "aws_security_group" "file_system" {
  name_prefix = "${local.name_prefix}-fs-"
  description = "Security group for S3 Files mount targets"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-fs-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nfs_from_compute" {
  count = length(var.compute_security_group_ids)

  security_group_id            = aws_security_group.file_system.id
  referenced_security_group_id = var.compute_security_group_ids[count.index]
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS from compute security group"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "vpc_only" {
  security_group_id = aws_security_group.file_system.id
  ip_protocol       = "-1"
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  description       = "Allow traffic within VPC only"

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Mount Targets (one per subnet/AZ)
# ------------------------------------------------------------------------------

resource "aws_s3files_mount_target" "this" {
  count = length(var.subnet_ids)

  file_system_id  = aws_s3files_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.file_system.id]
}

# ------------------------------------------------------------------------------
# File System Policy (resource-based access control)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "file_system_policy" {
  statement {
    sid    = "AllowMountFromPrincipals"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.allowed_principal_arns
    }

    actions = [
      "s3files:ClientMount",
      "s3files:ClientWrite",
      "s3files:ClientRootAccess",
    ]

    resources = [aws_s3files_file_system.this.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["*"]

    resources = [aws_s3files_file_system.this.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3files_file_system_policy" "this" {
  count = length(var.allowed_principal_arns) > 0 ? 1 : 0

  file_system_id = aws_s3files_file_system.this.id
  policy         = data.aws_iam_policy_document.file_system_policy.json
}

# ------------------------------------------------------------------------------
# Synchronization Configuration
# ------------------------------------------------------------------------------

resource "aws_s3files_synchronization_configuration" "this" {
  file_system_id = aws_s3files_file_system.this.id

  import_data_rule {
    prefix         = ""
    trigger        = var.import_trigger
    size_less_than = var.import_size_threshold
  }

  expiration_data_rule {
    days_after_last_access = var.expiration_days
  }
}

# ------------------------------------------------------------------------------
# Access Points (optional, for scoped access)
# ------------------------------------------------------------------------------

resource "aws_s3files_access_point" "this" {
  for_each = var.access_points

  file_system_id = aws_s3files_file_system.this.id

  posix_user {
    uid = try(each.value.posix_user.uid, 1000)
    gid = try(each.value.posix_user.gid, 1000)
  }

  root_directory {
    path = each.value.path

    dynamic "creation_permissions" {
      for_each = each.value.root_directory_creation_info != null ? [each.value.root_directory_creation_info] : []
      content {
        owner_uid   = creation_permissions.value.owner_uid
        owner_gid   = creation_permissions.value.owner_gid
        permissions = creation_permissions.value.permissions
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ap-${each.key}"
  })
}
