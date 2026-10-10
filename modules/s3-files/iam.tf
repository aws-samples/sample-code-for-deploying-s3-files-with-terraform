# ------------------------------------------------------------------------------
# IAM Policy Documents for Compute Access
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_s3files" {
  statement {
    sid = "S3FilesMount"
    actions = [
      "s3files:ClientMount",
      "s3files:ClientWrite",
      # EC2 mounts the file system root; without this, root is squashed and
      # writes to "/" fail with Permission denied (verified 2026-09-29)
      "s3files:ClientRootAccess",
      "s3files:GetFileSystem",
      "s3files:GetMountTarget",
    ]
    resources = [aws_s3files_file_system.this.arn]
  }

  # Direct reads from the linked bucket (large-file read performance)
  statement {
    sid       = "S3ObjectReadAccess"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${var.bucket_arn}/*"]
  }

  statement {
    sid       = "S3BucketListAccess"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }
}

resource "aws_iam_policy" "ec2_s3files" {
  name_prefix = "${local.name_prefix}-ec2-"
  description = "Allows EC2 instances to mount S3 file system ${aws_s3files_file_system.this.id}"
  policy      = data.aws_iam_policy_document.ec2_s3files.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "ecs_s3files" {
  statement {
    sid = "S3FilesMount"
    actions = [
      "s3files:ClientMount",
      "s3files:ClientWrite",
      "s3files:GetFileSystem",
      "s3files:GetMountTarget",
    ]
    resources = [aws_s3files_file_system.this.arn]
  }

  # Direct reads from the linked bucket (large-file read performance)
  statement {
    sid       = "S3ObjectReadAccess"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${var.bucket_arn}/*"]
  }

  statement {
    sid       = "S3BucketListAccess"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }

  # Only when access points exist: IAM rejects a statement with an empty resource list
  dynamic "statement" {
    for_each = length(aws_s3files_access_point.this) > 0 ? [1] : []
    content {
      sid = "S3FilesAccessPoint"
      actions = [
        "s3files:ClientMount",
        "s3files:ClientWrite",
      ]
      resources = [for ap in aws_s3files_access_point.this : ap.arn]
    }
  }
}

resource "aws_iam_policy" "ecs_s3files" {
  name_prefix = "${local.name_prefix}-ecs-"
  description = "Allows ECS tasks to mount S3 file system ${aws_s3files_file_system.this.id}"
  policy      = data.aws_iam_policy_document.ecs_s3files.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "lambda_s3files" {
  statement {
    sid = "S3FilesMount"
    actions = [
      "s3files:ClientMount",
      "s3files:ClientWrite",
      "s3files:GetFileSystem",
      "s3files:GetMountTarget",
    ]
    resources = [aws_s3files_file_system.this.arn]
  }

  # Direct reads from the linked bucket (large-file read performance)
  statement {
    sid       = "S3ObjectReadAccess"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${var.bucket_arn}/*"]
  }

  statement {
    sid       = "S3BucketListAccess"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }

  # Only when access points exist: IAM rejects a statement with an empty resource list
  dynamic "statement" {
    for_each = length(aws_s3files_access_point.this) > 0 ? [1] : []
    content {
      sid = "S3FilesAccessPoint"
      actions = [
        "s3files:ClientMount",
        "s3files:ClientWrite",
      ]
      resources = [for ap in aws_s3files_access_point.this : ap.arn]
    }
  }
}

resource "aws_iam_policy" "lambda_s3files" {
  name_prefix = "${local.name_prefix}-lambda-"
  description = "Allows Lambda functions to mount S3 file system ${aws_s3files_file_system.this.id}"
  policy      = data.aws_iam_policy_document.lambda_s3files.json

  tags = local.common_tags
}
