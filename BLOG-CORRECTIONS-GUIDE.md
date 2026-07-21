# Blog Post Corrections Guide — Exact Replacements

**For**: blog-post.md
**Status**: Code tested and deployed July 1, 2026. These are the EXACT corrections needed.

---

## Step 2: Replace file system resource block

**DELETE this:**
```hcl
resource "aws_s3files_file_system" "this" {
  bucket_name = var.bucket_name

  dynamic "encryption_configuration" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      kms_key_id = var.kms_key_arn
    }
  }

  tags = {
    Name        = "s3files-${var.environment}-${var.bucket_name}"
    Environment = var.environment
  }
}
```

**REPLACE with:**
```hcl
resource "aws_s3files_file_system" "this" {
  bucket                = var.bucket_arn
  role_arn              = var.role_arn
  kms_key_id            = var.kms_key_arn
  accept_bucket_warning = true

  tags = {
    Name        = "s3files-${var.environment}"
    Environment = var.environment
  }
}
```

**Update surrounding text:**
- Change "The dynamic block conditionally adds AWS KMS encryption" → "The `kms_key_id` argument optionally enables KMS encryption. When null, the file system uses SSE-S3 by default."
- ADD this paragraph: "The `role_arn` argument specifies an IAM role that grants the S3 Files service permission to synchronize data between the file system and S3 bucket. This role must trust `elasticfilesystem.amazonaws.com` and have S3 read/write permissions on the bucket plus EventBridge permissions for change detection. See Step 10 for the full role policy."
- Change `bucket_name` variable description to: "`bucket_arn` – ARN of the existing S3 general purpose bucket"

---

## Step 5: Replace synchronization section

**DELETE the resource block and replace with:**

```
Note: Synchronization in S3 Files is automatic by default. When you create a file system linked to a bucket, S3 Files handles bidirectional sync without additional configuration. Actively used data is copied to the file system for low-latency access, and writes are synchronized back to S3 as new object versions. You can customize import rules and data expiration through the synchronization configuration API or console.
```

Remove the `aws_s3files_synchronization_configuration` resource — the Terraform provider's schema for this resource does not support `sync_to_s3`/`sync_from_s3` nested blocks as shown.

---

## Step 6: Replace mount command

**DELETE:**
```bash
mount -t nfs4 \
  -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  ${file_system_dns}:/ ${mount_point}

echo "${file_system_dns}:/ ${mount_point} nfs4 nfsvers=4.1,..." >> /etc/fstab
```

**REPLACE with:**
```bash
#!/bin/bash
set -euo pipefail

# Install amazon-efs-utils (required for S3 Files mount helper)
dnf install -y amazon-efs-utils nfs-utils
mkdir -p ${mount_point}

# Mount using the mount helper (recommended — handles TLS, IAM, NFS v4.2)
mount -t efs -o tls,iam ${file_system_id}:/ ${mount_point}

# Persist across reboots
echo "${file_system_id}:/ ${mount_point} efs _netdev,tls,iam 0 0" >> /etc/fstab
```

**Update text:** Change "NFS v4.1" → "NFS v4.2" everywhere. Add note: "The mount helper automatically uses NFS v4.2, TLS encryption, IAM authentication, and optimal I/O settings. It also emits CloudWatch connectivity metrics."

---

## Step 7: Replace ECS task definition

**DELETE:**
```hcl
volume {
  name = "s3files-data"
  efs_volume_configuration {
    file_system_id     = module.s3_files.file_system_id
    transit_encryption = "ENABLED"
    authorization_config {
      access_point_id = module.s3_files.access_point_ids["app"]
      iam             = "ENABLED"
    }
  }
}
```

**REPLACE with:**
```hcl
volume {
  name = "s3files-data"
  s3files_volume_configuration {
    file_system_arn       = module.s3_files.file_system_arn
    root_directory        = "/"
    transit_encryption_port = 2999
    access_point_arn      = module.s3_files.access_point_arns["app"]
  }
}
```

**Update text:**
- Change "Amazon EFS volume configuration" → "S3 Files volume configuration (`s3filesVolumeConfiguration`)"
- Change "Transit encryption: Data encrypted in transit" → "Transit encryption is always enabled for S3 Files and cannot be disabled."
- Remove "iam = ENABLED" mention — IAM is handled via task role, not volume config
- Change "`file_system_id`" → "`file_system_arn`" (ARN, not ID)

---

## Step 9: Replace monitoring section entirely

**DELETE all CloudWatch code using `AWS/S3Files` namespace.**

**REPLACE with:**
```hcl
resource "aws_cloudwatch_metric_alarm" "nfs_connection" {
  alarm_name          = "s3files-${var.environment}-nfs-unreachable"
  alarm_description   = "S3 Files NFS mount target is not accessible from client"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "NFSConnectionAccessible"
  namespace           = "efs-utils/S3Files"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    FileSystemId = aws_s3files_file_system.this.id
  }
}
```

**Update text:**
- Change namespace from `AWS/S3Files` → `efs-utils/S3Files`
- Replace metric descriptions:
  - `NFSConnectionAccessible` — Can the client reach the mount target? (1=yes, 0=no)
  - `S3BucketAccessible` — Does the client have S3 permissions? (1=yes, 0=no)
  - `S3BucketReachable` — Is the bucket/prefix reachable? (1=yes, 0=no)
- Remove mentions of `SyncLagSeconds`, `SyncErrors`, `ClientConnections`, `DataReadBytes`, `DataWriteBytes` — these don't exist
- Add note: "These metrics are emitted by amazon-efs-utils on the client side, not by the S3 Files service. They require amazon-efs-utils to be installed on compute instances."

---

## Troubleshooting: ADD these rows

| Issue | Cause | Resolution |
|-------|-------|------------|
| `terraform destroy` fails with `BucketHasS3FileSystemAttached` | File system detachment is async | Wait 30 seconds and retry, or add `depends_on` to bucket versioning resource |
| Mount targets take 5+ minutes | Normal — ENI provisioning in each AZ | No action needed, wait for completion |
| `role_arn` error on create | Missing IAM role for S3 Files service | Create role trusting `elasticfilesystem.amazonaws.com` with S3 + EventBridge permissions |

---

## Yamini's Comments (RY1-RY6) Resolution

| Comment | Resolution |
|---------|------------|
| RY1: Service naming consistency | Apply throughout — expand on first mention, link to service page |
| RY2: NFS call-out needed? | Keep on first mention, then just "mount target" or "NFS traffic" after |
| RY3: Diagram formatting | Karthik to update diagram — remove restrictive lines |
| RY4/RY5: Be specific on compute egress | Add: "Amazon EC2 instances, Amazon ECS tasks, and AWS Lambda functions all need..." |
| RY6: `SyncLagSeconds` — is this a metric? | **NO — it's fabricated.** Replace entire monitoring section with correct `efs-utils/S3Files` metrics |

---

## Prerequisites: Update

Change: "AWS provider for Terraform v6.40.0 or later"
To: "AWS provider for Terraform v6.53.0 or later (confirmed working; earlier versions untested)"
