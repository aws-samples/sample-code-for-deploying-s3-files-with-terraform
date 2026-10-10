# ------------------------------------------------------------------------------
# Example: Mount S3 Files on Amazon EC2
# ------------------------------------------------------------------------------
#
# EC2 instances access S3 Files through the mount helper (amazon-efs-utils).
# The mount helper always applies TLS and IAM authentication and uses NFS v4.2.
# It also emits CloudWatch connectivity metrics to the efs-utils/S3Files namespace.
#
# Key points:
#   - Install amazon-efs-utils (provides the mount helper)
#   - Mount type is s3files: mount -t s3files <file-system-id>:/ <path>
#   - Instance needs s3files:ClientMount, ClientWrite, and ClientRootAccess (root mount)
#   - Instance must be in same VPC as mount targets
#   - Compute security group needs egress to mount target SG on port 2049 (main.tf)
#
# Reference: https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files-mounting.html
# ------------------------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "ec2_s3files" {
  name_prefix = "s3files-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3files" {
  role       = aws_iam_role.ec2_s3files.name
  policy_arn = module.s3_files.ec2_iam_policy_arn
}

# Lets the S3 Files client publish CloudWatch connectivity metrics (used by the module's alarms)
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_s3files.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemsUtils"
}

# Lets you connect to the private instance with Session Manager (no SSH or bastion)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_s3files.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_s3files" {
  name_prefix = "s3files-ec2-"
  role        = aws_iam_role.ec2_s3files.name
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.medium"
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3files.name
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.compute.id]

  # The boot-time mount needs the mount targets, which take several minutes to become available
  depends_on = [module.s3_files]

  user_data_base64 = base64encode(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    file_system_id = module.s3_files.file_system_id
    mount_point    = "/mnt/s3files"
  }))

  tags = {
    Name = "s3files-app-${var.environment}"
  }
}
