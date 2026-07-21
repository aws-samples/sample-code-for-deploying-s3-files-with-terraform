# Amazon S3 Files — Terraform Module

This repository contains a reusable Terraform module for deploying [Amazon S3 Files](https://aws.amazon.com/s3/files/) infrastructure, including file system creation, multi-AZ mount targets, security groups, IAM policies, synchronization configuration, and CloudWatch monitoring.

## Architecture

The module deploys the following resources:

- S3 file system attached to an existing general purpose bucket
- Mount targets in private subnets (one per Availability Zone)
- Security groups restricting NFS access (TCP 2049) to specified compute resources
- IAM policies for EC2, ECS, and Lambda with least-privilege permissions
- Synchronization configuration for bidirectional S3 sync
- Access points for scoped, per-application access
- CloudWatch alarms and dashboard for operational visibility

## Prerequisites

- AWS account with permissions to create S3 Files, VPC, IAM, and KMS resources
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest) >= 6.53.0
- An existing S3 general purpose bucket
- A VPC with private subnets in at least two Availability Zones

## Repository Structure

```
.
├── modules/
│   └── s3-files/
│       ├── main.tf            # File system, mount targets, security groups, access points
│       ├── iam.tf             # IAM policies for EC2, ECS, Lambda
│       ├── monitoring.tf      # CloudWatch alarms and dashboard
│       ├── variables.tf       # Input variables with validation
│       └── outputs.tf         # Exported values
├── environments/
│   ├── dev/
│   │   ├── main.tf           # Dev environment (self-contained with VPC, bucket, IAM)
│   │   └── variables.tf
│   └── prod/
│       ├── main.tf           # Prod environment configuration (KMS, existing VPC)
│       └── variables.tf
├── examples/
│   ├── ec2-s3files.tf         # EC2 instance with mount helper
│   ├── ecs-s3files.tf         # ECS Fargate task with S3 Files volume
│   ├── lambda-s3files.tf      # Lambda with file_system_config
│   ├── templates/
│   │   └── user-data.sh.tftpl # EC2 user data with mount helper
│   └── lambda-src/
│       └── index.py           # Sample Lambda handler
├── architecture-diagram.drawio # Architecture diagram (editable)
├── architecture-diagram.png    # Architecture diagram (rendered)
└── blog-post.md               # Accompanying blog post
```

## Quick Start

### 1. Deploy the dev environment

```bash
cd environments/dev

terraform init
terraform plan
terraform apply
```

The dev environment is fully self-contained — it creates its own VPC, subnets, S3 bucket, and IAM roles. No configuration required.

> **Note:** Configure AWS credentials before running. Use `aws configure`, set `AWS_PROFILE`, or any [standard authentication method](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration).

### 2. Mount on an EC2 instance

After deployment, SSH into an instance and verify the mount:

```bash
df -h /mnt/s3files
echo "Hello from EC2" > /mnt/s3files/test.txt

# Verify sync to S3 (allow up to 5 minutes)
aws s3 ls s3://my-app-data-dev/test.txt
```

## Module Usage

```hcl
module "s3_files" {
  source = "./modules/s3-files"

  environment = "prod"
  bucket_arn  = aws_s3_bucket.data.arn
  role_arn    = aws_iam_role.s3files_service.arn
  vpc_id      = "vpc-0abc123def456789a"
  subnet_ids  = ["subnet-aaa111", "subnet-bbb222"]

  compute_security_group_ids = [
    aws_security_group.app_servers.id,
  ]

  kms_key_arn            = aws_kms_key.s3files.arn
  allowed_principal_arns = [aws_iam_role.app.arn]

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

  tags = { Team = "platform" }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `environment` | Environment name (dev, staging, prod) | `string` | — | yes |
| `bucket_arn` | ARN of existing S3 bucket | `string` | — | yes |
| `role_arn` | IAM role ARN for S3 Files sync (must trust elasticfilesystem.amazonaws.com) | `string` | — | yes |
| `vpc_id` | VPC ID for mount targets | `string` | — | yes |
| `subnet_ids` | Private subnet IDs (one per AZ) | `list(string)` | — | yes |
| `compute_security_group_ids` | SG IDs of compute resources | `list(string)` | — | yes |
| `kms_key_arn` | KMS key ARN (null = SSE-S3) | `string` | `null` | no |
| `prefix` | S3 prefix to scope file system access | `string` | `null` | no |
| `enable_sync_to_s3` | Enable file system → S3 sync | `bool` | `true` | no |
| `enable_sync_from_s3` | Enable S3 → file system sync | `bool` | `true` | no |
| `access_points` | Map of access point configurations | `map(object)` | `{}` | no |
| `allowed_principal_arns` | IAM principals for file system policy | `list(string)` | `[]` | no |
| `vpc_arn` | VPC ARN (for Lambda ENI constraint) | `string` | `null` | no |
| `private_subnet_arns` | Subnet ARNs (for Lambda ENI constraint) | `list(string)` | `[]` | no |
| `tags` | Additional tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `file_system_id` | ID of the S3 file system |
| `file_system_arn` | ARN of the S3 file system |
| `mount_target_ids` | Map of subnet ID → mount target ID |
| `mount_target_ips` | Map of subnet ID → mount target IP |
| `security_group_id` | Security group ID for mount targets |
| `access_point_ids` | Map of access point name → ID |
| `access_point_arns` | Map of access point name → ARN |
| `ec2_iam_policy_arn` | IAM policy ARN for EC2 instances |
| `ecs_iam_policy_arn` | IAM policy ARN for ECS tasks |
| `lambda_iam_policy_arn` | IAM policy ARN for Lambda functions |
| `mount_helper_command` | Ready-to-use mount command (recommended) |

## Security

This module implements the following security controls:

- **Encryption at rest** — SSE-S3 (default) or customer-managed KMS with automatic key rotation
- **Encryption in transit** — File system policy denies insecure transport; ECS uses transit encryption
- **Network isolation** — Mount targets in private subnets only; security groups reference by ID
- **Least-privilege IAM** — Separate policies per compute type scoped to specific file system ARN
- **KMS key policy** — Grants S3 Files service principal via `kms:ViaService` condition

## Environment Differences

| Setting | Dev | Prod |
|---------|-----|------|
| Encryption | SSE-S3 | Customer-managed KMS |
| Mount targets | 2 AZs | 3 AZs |
| File system policy | None | Explicit principal allowlist |
| State backend | S3 | S3 + DynamoDB locking |
| Access points | 1 | Multiple |

## Cleaning Up

```bash
# Unmount from compute resources first
sudo umount /mnt/s3files

# Destroy Terraform resources
terraform destroy
```

Destroying the file system does **not** delete S3 objects. Your data remains in the bucket.

## Related Resources

- [Amazon S3 Files documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files.html)
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS KMS best practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-kms-best-practices/introduction.html)

## License

This sample code is made available under the MIT-0 license. See the LICENSE file.
