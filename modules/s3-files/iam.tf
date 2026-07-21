# ------------------------------------------------------------------------------
# IAM Policy Documents for Compute Access
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_s3files" {
  statement {
    sid = "S3FilesMount"
    actions = [
      "s3files:ClientMount",
      "s3files:ClientWrite",
      "s3files:DescribeFileSystems",
      "s3files:DescribeMountTargets",
    ]
    resources = [aws_s3files_file_system.this.arn]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid = "KMSDecrypt"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
      ]
      resources = [var.kms_key_arn]
    }
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
      "s3files:DescribeFileSystems",
      "s3files:DescribeMountTargets",
    ]
    resources = [aws_s3files_file_system.this.arn]
  }

  statement {
    sid = "S3FilesAccessPoint"
    actions = [
      "s3files:ClientMount",
      "s3files:ClientWrite",
    ]
    resources = [for ap in aws_s3files_access_point.this : ap.arn]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid = "KMSDecrypt"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
      ]
      resources = [var.kms_key_arn]
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
      "s3files:DescribeFileSystems",
      "s3files:DescribeMountTargets",
    ]
    resources = [aws_s3files_file_system.this.arn]
  }

  statement {
    sid = "S3FilesAccessPoint"
    actions = [
      "s3files:ClientMount",
      "s3files:ClientWrite",
    ]
    resources = [for ap in aws_s3files_access_point.this : ap.arn]
  }

  statement {
    sid = "VPCNetworkInterfacesDescribe"
    actions = [
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }

  statement {
    sid = "VPCNetworkInterfacesMutate"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:Vpc"
      values   = [var.vpc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:Subnet"
      values   = var.private_subnet_arns
    }
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid = "KMSDecrypt"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "lambda_s3files" {
  name_prefix = "${local.name_prefix}-lambda-"
  description = "Allows Lambda functions to mount S3 file system ${aws_s3files_file_system.this.id}"
  policy      = data.aws_iam_policy_document.lambda_s3files.json

  tags = local.common_tags
}
