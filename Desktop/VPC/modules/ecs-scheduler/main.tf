data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda/index.zip"
}

# Lambda
resource "aws_lambda_function" "scheduler" {
  function_name    = "${var.env}-ecs-scheduler"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER = var.ecs_cluster_name
      ECS_SERVICE = var.ecs_service_name
    }
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name = "${var.env}-scheduler-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.env}-scheduler-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster_name}/${var.ecs_service_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# EventBridge Scheduler IAM Role
resource "aws_iam_role" "scheduler" {
  name = "${var.env}-scheduler-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.env}-scheduler-eventbridge-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.scheduler.arn
    }]
  })
}

# Schedule: Start (평일 오전 9시 KST)
resource "aws_scheduler_schedule" "start" {
  name       = "${var.env}-ecs-start"
  group_name = "default"

  schedule_expression          = var.start_schedule
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.scheduler.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "start" })
  }
}

# Schedule: Stop (평일 오후 6시 KST)
resource "aws_scheduler_schedule" "stop" {
  name       = "${var.env}-ecs-stop"
  group_name = "default"

  schedule_expression          = var.stop_schedule
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.scheduler.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "stop" })
  }
}
