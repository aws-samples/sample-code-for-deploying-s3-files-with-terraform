# ------------------------------------------------------------------------------
# CloudWatch Alarms for S3 Files
# ------------------------------------------------------------------------------
#
# The S3 Files client (amazon-efs-utils) publishes connectivity metrics to the
# "efs-utils/S3Files" namespace, one series per client:
#
#   - S3BucketAccessible: Does the client have permission to read the linked bucket?
#   - S3BucketReachable:  Is the linked bucket and prefix reachable from the client?
#
# Dimensions are Bucket + InstanceId (not FileSystemId), so each alarm uses a
# CloudWatch Metrics Insights query that takes the minimum across all clients of
# this bucket. Values are 1 = healthy, 0 = unhealthy. No clients mounted means
# no data, which is treated as not breaching.
#
# NFSConnectionAccessible is documented, but efs-proxy only publishes it when
# read bypass is enabled (verified against amazon-efs-utils source and a live
# test on 2026-09-29), so this module does not alarm on it.
# ------------------------------------------------------------------------------

locals {
  bucket_name = replace(var.bucket_arn, "arn:aws:s3:::", "")

  client_metrics = {
    s3_bucket_accessible = {
      metric      = "S3BucketAccessible"
      alarm       = "s3-permissions"
      description = "An S3 Files client lacks permission to read the linked S3 bucket"
    }
    s3_bucket_reachable = {
      metric      = "S3BucketReachable"
      alarm       = "s3-unreachable"
      description = "The linked S3 bucket or prefix is not reachable from an S3 Files client"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "client" {
  for_each = local.client_metrics

  alarm_name          = "${local.name_prefix}-${each.value.alarm}"
  alarm_description   = each.value.description
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  threshold           = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "q1"
    return_data = true
    period      = 300
    expression  = "SELECT MIN(${each.value.metric}) FROM SCHEMA(\"efs-utils/S3Files\", Bucket, InstanceId) WHERE Bucket = '${local.bucket_name}'"
  }

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# CloudWatch Dashboard — one line per client for each metric
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "s3files" {
  dashboard_name = "${local.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      for i, m in values(local.client_metrics) : {
        type   = "metric"
        x      = i * 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "${m.metric} (per client)"
          region = data.aws_region.current.region
          period = 300
          stat   = "Minimum"
          yAxis  = { left = { min = 0, max = 1 } }
          metrics = [[{
            expression = "SELECT MIN(${m.metric}) FROM SCHEMA(\"efs-utils/S3Files\", Bucket, InstanceId) WHERE Bucket = '${local.bucket_name}' GROUP BY InstanceId"
            id         = "q${i}"
            label      = m.metric
          }]]
        }
      }
    ]
  })
}
