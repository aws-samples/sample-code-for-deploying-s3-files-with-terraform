# ------------------------------------------------------------------------------
# Example: Mount S3 Files on AWS Lambda
# ------------------------------------------------------------------------------
#
# Lambda accesses S3 Files through access points, similar to EFS.
# The function must be in the same VPC as the mount targets.
#
# Key points:
#   - Access point ARN required (not file system ARN directly)
#   - Local mount path must start with /mnt/
#   - Function needs s3files:ClientMount and s3files:ClientWrite permissions
#   - For direct S3 reads on large files (>=1 MiB), also add s3:GetObject
#   - Recommend 512 MB+ memory for optimal throughput on large files
#   - VPC-attached Lambda has longer cold starts (1-5s); use provisioned concurrency
#
# Reference: https://docs.aws.amazon.com/lambda/latest/dg/configuration-filesystem-s3files.html
# ------------------------------------------------------------------------------

resource "aws_lambda_function" "processor" {
  function_name = "s3files-processor-${var.environment}"
  role          = aws_iam_role.lambda_s3files.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 512

  filename         = data.archive_file.lambda_src.output_path
  source_code_hash = data.archive_file.lambda_src.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.compute.id]
  }

  # S3 Files uses the same file_system_config block as EFS in Terraform.
  # The access_point_arn distinguishes S3 Files from EFS at the service level.
  file_system_config {
    arn              = module.s3_files.access_point_arns["app"]
    local_mount_path = "/mnt/s3data"
  }

  environment {
    variables = {
      MOUNT_PATH = "/mnt/s3data"
    }
  }
}

data "archive_file" "lambda_src" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-src"
  output_path = "${path.module}/.build/lambda.zip"
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_s3files" {
  name_prefix = "s3files-lambda-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3files" {
  role       = aws_iam_role.lambda_s3files.name
  policy_arn = module.s3_files.lambda_iam_policy_arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_s3files.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_s3files.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Optional: For direct S3 reads on large files (>=1 MiB), add s3:GetObject
resource "aws_iam_role_policy" "lambda_s3_direct_read" {
  name = "s3-direct-read"
  role = aws_iam_role.lambda_s3files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DirectS3Read"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion",
      ]
      Resource = "arn:aws:s3:::${var.bucket_name}/*"
    }]
  })
}
