# Phase 2 — 1분마다 canary 깨우기 (EventBridge Scheduler)
# 사람이 부르지 않아도 도쿄 canary가 1분 간격으로 서울을 probe 한다.

# Scheduler가 canary를 부를 수 있는 역할
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "scheduler" {
  name               = "dr-brain-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}
resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-canary"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.canary.arn
    }]
  })
}

# 1분마다 canary 실행
resource "aws_scheduler_schedule" "canary" {
  name = "dr-brain-canary-1min"
  flexible_time_window {
    mode = "OFF"
  }
  schedule_expression = "rate(1 minute)"
  target {
    arn      = aws_lambda_function.canary.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "schedule" })
  }
}
