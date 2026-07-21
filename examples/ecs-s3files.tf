# ------------------------------------------------------------------------------
# Example: Mount S3 Files on Amazon ECS (Fargate)
# ------------------------------------------------------------------------------
#
# S3 Files integrates with ECS through the s3filesVolumeConfiguration
# parameter in the task definition volume block. This is DIFFERENT from
# the efs_volume_configuration used for Amazon EFS.
#
# Key differences from EFS:
#   - Uses file_system_arn (not file_system_id)
#   - Transit encryption is ALWAYS enabled (cannot be disabled)
#   - Uses transit_encryption_port (optional, not a boolean toggle)
#   - IAM authorization is handled via task role, not volume config
#
# Reference: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/s3files-volumes.html
# ------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = "s3files-app-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  task_role_arn            = aws_iam_role.ecs_task.arn
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  volume {
    name = "s3files-data"

    s3files_volume_configuration {
      file_system_arn       = module.s3_files.file_system_arn
      root_directory        = "/"
      transit_encryption_port = 2999
      access_point_arn      = module.s3_files.access_point_arns["app"]
    }
  }

  container_definitions = jsonencode([{
    name                   = "app"
    image                  = "my-app:latest"
    essential              = true
    readonlyRootFilesystem = true
    mountPoints = [{
      sourceVolume  = "s3files-data"
      containerPath = "/data"
      readOnly      = false
    }]
  }])
}

# Note: Fargate platform version 1.4.0 or later required.
resource "aws_ecs_service" "app" {
  name             = "s3files-app-${var.environment}"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.app.arn
  desired_count    = 2
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.compute.id]
  }
}

# IAM role for ECS task — needs s3files:ClientMount and s3files:ClientWrite
resource "aws_iam_role" "ecs_task" {
  name_prefix = "s3files-ecs-task-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_s3files" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = module.s3_files.ecs_iam_policy_arn
}

resource "aws_iam_role" "ecs_execution" {
  name_prefix = "s3files-ecs-exec-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
