# Terraform Validation — Test Results & Fixes

**Date**: July 1, 2026
**Terraform version**: 1.15.7
**AWS Provider**: v6.53.0 (hashicorp/aws)
**Tester**: Satyadev S (srirajam)

---

## Test 1: `terraform init` — ✅ PASSED

```
- Finding hashicorp/aws versions matching ">= 6.40.0"...
- Installing hashicorp/aws v6.53.0...
- Installed hashicorp/aws v6.53.0 (signed by HashiCorp)
```

**Conclusion**: AWS provider v6.53.0 DOES include `aws_s3files_*` resources. The blog's prerequisite of "v6.40.0 or later" needs verification — it's v6.53.0 that was installed. The minimum version may be lower but 6.40.0 is unconfirmed.

---

## Test 2: `terraform validate` — ❌ FAILED (4 errors)

### Error 1: Missing required argument `role_arn`
```
Error: Missing required argument
  on main.tf line 31, in resource "aws_s3files_file_system" "this":
  31: resource "aws_s3files_file_system" "this" {
The argument "role_arn" is required, but no definition was found.
```

**Root cause**: The S3 Files service requires an IAM role ARN that grants it permission to:
- Read/write the S3 bucket and objects (for sync)
- Manage EventBridge rules (prefixed `DO-NOT-DELETE-S3-Files`) for change detection

This role must trust `elasticfilesystem.amazonaws.com` as the service principal.

**Fix**: Add `role_arn` variable and pass it to the resource. Add the role creation in environments/prod and environments/dev.

### Error 2: Missing required argument `bucket`
```
Error: Missing required argument
  on main.tf line 31, in resource "aws_s3files_file_system" "this":
  31: resource "aws_s3files_file_system" "this" {
The argument "bucket" is required, but no definition was found.
```

**Root cause**: The Terraform resource uses `bucket` (which takes the **bucket ARN**), not `bucket_name`.

**Fix**: Rename `bucket_name` → `bucket_arn` in variables and use `bucket = var.bucket_arn` in the resource.

### Error 3: Unsupported argument `bucket_name`
```
Error: Unsupported argument
  on main.tf line 32, in resource "aws_s3files_file_system" "this":
  32:   bucket_name = var.bucket_name
An argument named "bucket_name" is not expected here.
```

**Root cause**: Same as Error 2 — the argument is `bucket`, not `bucket_name`.

### Error 4: Unsupported block type `encryption_configuration`
```
Error: Unsupported block type
  on main.tf line 34, in resource "aws_s3files_file_system" "this":
  34:   dynamic "encryption_configuration" {
Blocks of type "encryption_configuration" are not expected here.
```

**Root cause**: The resource uses `kms_key_id` as a top-level argument, not a nested `encryption_configuration` block.

**Fix**: Replace the dynamic block with: `kms_key_id = var.kms_key_arn`

---

## Correct `aws_s3files_file_system` Resource Schema

From CDK/API documentation (verified against provider v6.53.0):

```hcl
resource "aws_s3files_file_system" "this" {
  bucket                        = var.bucket_arn       # Required — S3 bucket ARN
  role_arn                      = var.role_arn         # Required — IAM role for S3 Files sync
  kms_key_id                    = var.kms_key_arn     # Optional — KMS key ARN
  prefix                        = var.prefix          # Optional — scope to bucket prefix
  accept_bucket_warning         = true                # Optional — acknowledge bucket config warnings

  synchronization_configuration {                      # Optional — nested block
    # import/expiration rules
  }

  tags = { ... }
}
```

### Required IAM Role for S3 Files

The role must:
1. Trust `elasticfilesystem.amazonaws.com` as service principal
2. Have S3 permissions: `s3:ListBucket*`, `s3:GetObject*`, `s3:PutObject*`, `s3:DeleteObject`, `s3:AbortMultipartUpload`
3. Have EventBridge permissions: `events:PutRule`, `events:PutTargets`, `events:DeleteRule`, `events:DisableRule`, `events:EnableRule`, `events:RemoveTargets`
4. Have EventBridge list permission: `events:ListRules` (for monitoring)

---

## Additional Schema Discoveries

### `aws_s3files_mount_target`
Based on the CDK `CfnMountTarget`, the mount target likely needs:
- `file_system_id` — ✅ matches current code
- `subnet_id` — ✅ matches current code
- `security_groups` — ✅ matches current code

### `aws_s3files_file_system_policy`
- `file_system_id` — ✅ matches current code
- `policy` — ✅ matches current code

### `aws_s3files_access_point`
Based on CDK `CfnAccessPoint`:
- `file_system_id` — ✅ matches current code
- Need to verify exact block structure for `posix_user` and `root_directory`

---

## Next Steps

1. ~~Fix `main.tf` — replace `bucket_name` with `bucket`, add `role_arn`, remove `encryption_configuration` block~~ ✅ DONE
2. ~~Fix `variables.tf` — rename variable, add `role_arn` and `prefix` variables~~ ✅ DONE
3. ~~Add IAM role for S3 Files service in environments/prod and environments/dev~~ ✅ DONE
4. ~~Re-run `terraform validate`~~ ✅ PASSED
5. ~~Continue fixing until clean~~ ✅ ALL CLEAN
6. ~~Deploy and test~~ ✅ DEPLOYED + DESTROYED SUCCESSFULLY
7. Update blog post to reflect correct arguments

---

## Test 3: `terraform plan` — ✅ PASSED (after fixes)

Plan: 21 to add, 0 to change, 0 to destroy.

Additional fixes required during plan:
- `for_each` with unknown SG IDs → switched to `count`
- `ip_address` attribute → corrected to `ipv4_address`

## Test 4: `terraform apply` — ✅ PASSED

**Account**: 854435129789 (optima-desktop profile)
**Region**: us-east-1
**VPC**: vpc-055fce2c0b4b5bd5c

Resources created:
```
aws_s3_bucket.test                          → s3files-blog-dev-0fd9d7bc871aec69623ee1318b
aws_s3_bucket_versioning.test               → Enabled
aws_iam_role.s3files_service                → s3files-dev-service-5e909567e614e95c1919f29025
aws_iam_role_policy.s3files_s3_access       → S3 read/write
aws_iam_role_policy.s3files_eventbridge     → EventBridge manage
aws_security_group.compute                  → sg-0fc94c382bce738a8
aws_vpc_security_group_egress_rule          → compute → FS (port 2049)
module.s3_files.aws_s3files_file_system     → fs-01ad1b85421b8ad13 (21s to create)
module.s3_files.aws_s3files_mount_target x2 → fsmt-0dbfd384e67066aa9, fsmt-0b4c245d472a4ce9b (4m57s)
module.s3_files.aws_s3files_access_point    → fsap-0ae61dcc053ad0098
module.s3_files.aws_security_group          → sg-04ab7b2517f668950
module.s3_files.aws_vpc_security_group_*    → ingress + egress rules
module.s3_files.aws_cloudwatch_*            → 3 alarms + 1 dashboard
module.s3_files.aws_iam_policy x3           → EC2, ECS, Lambda policies
```

**Timing**:
- File system creation: 21 seconds
- Mount target creation: 4 minutes 57 seconds (both in parallel)
- Total apply: ~5 minutes 30 seconds

**Mount command output**: `sudo mount -t efs -o tls,iam fs-01ad1b85421b8ad13:/ /mnt/s3files`

## Test 5: `terraform destroy` — ✅ PASSED (with learning)

**Issue encountered**: First destroy attempt failed with:
```
Error: deleting S3 Bucket Versioning: BucketHasS3FileSystemAttached:
Bucket has an S3 file system attached and versioning state cannot be changed.
```

**Root cause**: Terraform destroyed the bucket versioning resource before the S3 Files service fully detached from the bucket (race condition — file system destroy returns but detachment is async).

**Fix applied**: Added `depends_on = [module.s3_files]` to `aws_s3_bucket_versioning` resource so it's destroyed after the file system module.

**Second run**: Clean destroy, all resources removed.

---

## All Fixes Summary (11 total)

| # | Error | Fix Applied |
|---|-------|-------------|
| 1 | `bucket_name` not supported | → `bucket` (takes ARN) |
| 2 | `role_arn` required (missing) | → Added as required variable |
| 3 | `encryption_configuration` block unsupported | → Flat `kms_key_id` argument |
| 4 | `tags` on mount target unsupported | → Removed |
| 5 | `sync_to_s3`/`sync_from_s3` blocks unsupported | → Commented out (schema TBD) |
| 6 | `creation_info` block in access point unsupported | → Removed |
| 7 | `name` on access point is read-only | → Removed |
| 8 | `dns_name` attribute doesn't exist | → Use `file_system_id` with mount helper |
| 9 | `data.aws_region.current.name` deprecated | → `.region` |
| 10 | `for_each` with unknown SG IDs | → `count` |
| 11 | `ip_address` attribute wrong | → `ipv4_address` |

---

## Blog Post Impact

The following blog sections contain incorrect code that readers would not be able to deploy:

| Section | Wrong | Correct |
|---------|-------|---------|
| Step 2 | `bucket_name = var.bucket_name` | `bucket = var.bucket_arn` (ARN, not name) |
| Step 2 | No `role_arn` | `role_arn = var.role_arn` (REQUIRED) |
| Step 2 | `dynamic "encryption_configuration"` | `kms_key_id = var.kms_key_arn` (flat) |
| Step 5 | `sync_to_s3 { enabled = ... }` | Resource schema doesn't support nested blocks |
| Step 6 | `nfsvers=4.1` | `nfsvers=4.2` |
| Step 6 | No mount helper | Mount helper is the recommended approach |
| Step 7 | `efs_volume_configuration` | `s3files_volume_configuration` |
| Step 9 | `namespace = "AWS/S3Files"` | `namespace = "efs-utils/S3Files"` |
| Step 9 | `SyncLagSeconds`, `ClientConnections` | `NFSConnectionAccessible`, `S3BucketAccessible`, `S3BucketReachable` |
| Prerequisites | "v6.40.0" | Confirmed working on v6.53.0 (6.40.0 unverified) |
| Troubleshooting | — | Add: destroy order (detach FS before disabling versioning) |
| Troubleshooting | — | Add: mount targets take ~5 minutes to provision |
