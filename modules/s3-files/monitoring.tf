# ------------------------------------------------------------------------------
# CloudWatch Alarms for S3 Files
# ------------------------------------------------------------------------------
#
# S3 Files client metrics are emitted by amazon-efs-utils to the
# "efs-utils/S3Files" namespace. These are client-side connectivity
# health checks (0 = unhealthy, 1 = healthy).
#
# Metrics:
#   - NFSConnectionAccessible: Can the client reach the mount target via NFS?
#   - S3BucketAccessible: Does the client have permissions to read the linked bucket?
#   - S3BucketReachable: Is the linked bucket and prefix reachable from the client?
#
# Note: These metrics require amazon-efs-utils to be installed on compute
# instances. They are emitted per-client, not per-file-system.
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "nfs_connection" {
  alarm_name          = "${local.name_prefix}-nfs-unreachable"
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

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "s3_bucket_accessible" {
  alarm_name          = "${local.name_prefix}-s3-permissions"
  alarm_description   = "S3 Files client lacks permissions to read the linked S3 bucket"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "S3BucketAccessible"
  namespace           = "efs-utils/S3Files"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_s3files_file_system.this.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "s3_bucket_reachable" {
  alarm_name          = "${local.name_prefix}-s3-unreachable"
  alarm_description   = "S3 Files linked bucket or prefix is not reachable from client"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "S3BucketReachable"
  namespace           = "efs-utils/S3Files"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_s3files_file_system.this.id
  }

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# CloudWatch Dashboard
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "s3files" {
  dashboard_name = "${local.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "NFS Connection Health"
          metrics = [["efs-utils/S3Files", "NFSConnectionAccessible", "FileSystemId", aws_s3files_file_system.this.id]]
          period  = 300
          region  = data.aws_region.current.region
          yAxis   = { left = { min = 0, max = 1 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "S3 Bucket Permissions"
          metrics = [["efs-utils/S3Files", "S3BucketAccessible", "FileSystemId", aws_s3files_file_system.this.id]]
          period  = 300
          region  = data.aws_region.current.region
          yAxis   = { left = { min = 0, max = 1 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "S3 Bucket Reachability"
          metrics = [["efs-utils/S3Files", "S3BucketReachable", "FileSystemId", aws_s3files_file_system.this.id]]
          period  = 300
          region  = data.aws_region.current.region
          yAxis   = { left = { min = 0, max = 1 } }
        }
      },
    ]
  })
}
