# Amazon S3 Files — Terraform Module

This repository contains a reusable Terraform module for deploying [Amazon S3 Files](https://aws.amazon.com/s3/files/) infrastructure, including file system creation, multi-AZ mount targets, security groups, IAM policies, synchronization configuration, and CloudWatch monitoring.

## Architecture

The module deploys the following resources:

- S3 file system attached to an existing general purpose bucket
- Mount targets in private subnets (one per Availability Zone)
- Security groups restricting NFS access (TCP 2049) to specified compute resources
- IAM policies for EC2, ECS, and Lambda with least-privilege permissions
- Synchronization configuration (import and expiration rules)
- Access points for scoped, per-application access
- CloudWatch alarms and dashboard for operational visibility

## Prerequisites

- AWS account with permissions to create S3 Files, VPC, IAM, and KMS resources
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest) >= 6.58.0 (tested with 6.58.0 and 6.68.0)
- An S3 general purpose bucket with versioning enabled
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
├── examples/                  # Standalone root configurations (bring your own VPC and bucket)
│   ├── ec2/                   # EC2 instance that mounts the file system at boot
│   │   ├── main.tf            # Service role, compute security group, module call
│   │   ├── ec2.tf             # Instance, instance profile, IAM role
│   │   ├── templates/user-data.sh.tftpl
│   │   ├── variables.tf · outputs.tf · versions.tf
│   │   └── terraform.auto.tfvars.example
│   ├── ecs/                   # ECS Fargate task with an S3 Files volume
│   │   ├── main.tf · ecs.tf · variables.tf · outputs.tf · versions.tf
│   │   └── terraform.auto.tfvars.example
│   └── lambda/                # Lambda function with file_system_config
│       ├── main.tf · lambda.tf · variables.tf · outputs.tf · versions.tf
│       ├── lambda-src/index.py
│       └── terraform.auto.tfvars.example
├── architecture-diagram.drawio # Architecture diagram (editable)
├── architecture-diagram.png    # Architecture diagram (rendered)
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
└── LICENSE
```

## Quick Start

Choose one path.

### Option A: Build everything from scratch (`environments/dev`)

Creates its own VPC, private subnets, versioned S3 bucket, service role, and the S3 file system. No inputs required.

```bash
git clone https://github.com/aws-samples/sample-code-for-deploying-s3-files-with-terraform.git
cd sample-code-for-deploying-s3-files-with-terraform/environments/dev

terraform init
terraform plan
terraform apply
```

### Option B: Use your existing VPC and bucket (`examples/<compute>`)

Each folder under `examples/` is a complete root configuration: provider, service role, compute security group, the module call, and the compute resource. You provide:

- A VPC with private subnets in at least two Availability Zones
- Outbound access from those subnets (NAT gateway or VPC endpoints) so EC2 can install `amazon-efs-utils` and Fargate can pull the container image
- An S3 general purpose bucket with versioning enabled

```bash
git clone https://github.com/aws-samples/sample-code-for-deploying-s3-files-with-terraform.git
cd sample-code-for-deploying-s3-files-with-terraform/examples/ec2   # or ecs, lambda

cp terraform.auto.tfvars.example terraform.auto.tfvars
# Edit terraform.auto.tfvars with your VPC, subnet, and bucket values

terraform init
terraform plan
terraform apply
```

Apply one example at a time per account and environment: the module names its alarms and dashboard after the environment.

Verify each example:

| Example | Verify |
|---|---|
| `ec2` | `$(terraform output -raw connect_command)`, then `df -h /mnt/s3files` and `echo hello \| sudo tee /mnt/s3files/test.txt` |
| `ecs` | `aws logs tail $(terraform output -raw log_group_name)` shows the `ls -l /data` listing |
| `lambda` | `$(terraform output -raw invoke_command)` returns the files under `/mnt/s3data` |

Files written through the mount are exported to the bucket about 60 seconds after the last write.

Timing notes from testing:

- Mount targets take about 5 minutes to create. The examples make the EC2 instance, ECS service, and Lambda function wait for them.
- The first Lambda invocation right after `terraform apply` can fail with `S3FilesMountTimeoutException`. Wait about a minute and invoke again.
- `terraform destroy` of the Lambda example takes several minutes while Lambda detaches its network interfaces. If you then delete the VPC or subnets yourself, wait for those Lambda-managed interfaces to be released (often 20 minutes or more).

> **Note:** Configure AWS credentials before running. Use `aws configure`, set `AWS_PROFILE`, or any [standard authentication method](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration).

## Module Usage

To call the module from your own configuration, reference it by Git tag. Every value below is a literal or a placeholder you replace; the service role must already exist (see `examples/ec2/main.tf` for a complete role definition).

```hcl
module "s3_files" {
  source = "git::https://github.com/aws-samples/sample-code-for-deploying-s3-files-with-terraform.git//modules/s3-files?ref=v1.0.0"

  environment = "prod"
  bucket_arn  = "arn:aws:s3:::amzn-s3-demo-bucket"
  role_arn    = "arn:aws:iam::111122223333:role/s3files-service"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]

  compute_security_group_ids = ["sg-0123456789abcdef0"]

  kms_key_arn            = null # Set to your KMS key ARN to use a customer-managed key
  allowed_principal_arns = ["arn:aws:iam::111122223333:role/app"]

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
| `import_trigger` | `ON_DIRECTORY_FIRST_ACCESS` or `ON_FILE_ACCESS` | `string` | `ON_DIRECTORY_FIRST_ACCESS` | no |
| `import_size_threshold` | Import file data below this size (bytes) | `number` | `131072` | no |
| `expiration_days` | Days without a read before data expires from the file system | `number` | `30` | no |
| `accept_bucket_warning` | Acknowledge the large-bucket (~12M objects) warning | `bool` | `false` | no |
| `access_points` | Map of access point configurations | `map(object)` | `{}` | no |
| `allowed_principal_arns` | IAM principals for file system policy | `list(string)` | `[]` | no |
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
- **Encryption in transit** — Always TLS (mount helper and ECS); file system policy also denies insecure transport
- **Network isolation** — Mount targets in private subnets only; security groups reference by ID
- **Least-privilege IAM** — Separate policies per compute type scoped to specific file system ARN
- **KMS** — `kms_key_arn` encrypts the file system layer; the default key policy is sufficient. Bucket objects use the bucket's own encryption setting

## Environment Differences

| Setting | Dev | Prod |
|---------|-----|------|
| Encryption | SSE-S3 | Customer-managed KMS |
| Mount targets | 2 AZs | 3 AZs |
| File system policy | None | Explicit principal allowlist |
| State backend | Local | S3 + DynamoDB locking |
| Access points | 1 | Multiple |

## Cleaning Up

```bash
# From the folder you applied (environments/dev or examples/<compute>)
terraform destroy
```

Destroying the file system does **not** delete S3 objects. Your data remains in the bucket.

## Related Resources

- [Amazon S3 Files documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files.html)
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS KMS best practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-kms-best-practices/introduction.html)

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
