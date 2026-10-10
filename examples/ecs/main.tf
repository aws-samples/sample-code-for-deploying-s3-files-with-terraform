# ------------------------------------------------------------------------------
# S3 Files for Amazon ECS on AWS Fargate: service role, compute security group, and module
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# IAM role that S3 Files assumes to synchronize data with the bucket
# ------------------------------------------------------------------------------

resource "aws_iam_role" "s3files_service" {
  name_prefix = "s3files-ecs-service-"

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
        Resource = [var.bucket_arn]
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
        Resource = ["${var.bucket_arn}/*"]
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
# Security group for the compute resource that mounts the file system
# ------------------------------------------------------------------------------

resource "aws_security_group" "compute" {
  name_prefix = "s3files-ecs-compute-"
  description = "Compute resources that mount S3 Files"
  vpc_id      = var.vpc_id
}

# NFS to the mount targets (the module allows this inbound from the compute security group)
resource "aws_vpc_security_group_egress_rule" "compute_to_fs" {
  security_group_id            = aws_security_group.compute.id
  referenced_security_group_id = module.s3_files.security_group_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS to S3 Files mount targets"
}

# Outbound HTTPS so the compute resource can reach package repositories, ECR, and AWS APIs
resource "aws_vpc_security_group_egress_rule" "compute_https" {
  security_group_id = aws_security_group.compute.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS egress"
}

# ------------------------------------------------------------------------------
# S3 Files module: file system, mount targets, policies, sync, and monitoring
# ------------------------------------------------------------------------------

module "s3_files" {
  source = "../../modules/s3-files"

  # The service role needs its permissions before the file system is created
  depends_on = [
    aws_iam_role_policy.s3files_s3_access,
    aws_iam_role_policy.s3files_eventbridge,
  ]

  environment = var.environment
  bucket_arn  = var.bucket_arn
  role_arn    = aws_iam_role.s3files_service.arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  compute_security_group_ids = [aws_security_group.compute.id]

  # Access point the compute resource mounts (enforces POSIX identity and a root directory)
  access_points = {
    app = {
      path       = "/app-data"
      posix_user = { uid = 1000, gid = 1000 }
      root_directory_creation_info = {
        owner_uid   = 1000
        owner_gid   = 1000
        permissions = "755"
      }
    }
  }
}
