# Phase 2 — 감시 탐지기(detect_canary) : 도쿄가 서울을 밖에서 들여다본다
# VPC 불필요(공개 엔드포인트만 본다). dr-1에서 만든 lambda_assume(iam.tf)를 그대로 재사용.
data "archive_file" "canary" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/detect_canary"
  output_path = "${path.module}/build/canary.zip"
}

resource "aws_iam_role" "canary" {
  name               = "dr-brain-canary-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "canary_logs" {
  role       = aws_iam_role.canary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "canary" {
  name = "canary-perms"
  role = aws_iam_role.canary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.coordinator.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.approvals.arn
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics"]
        Resource = "*"
      }
    ]
  })
}
resource "aws_lambda_function" "canary" {
  function_name    = "dr-brain-canary"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 15
  filename         = data.archive_file.canary.output_path
  source_code_hash = data.archive_file.canary.output_base64sha256
  role             = aws_iam_role.canary.arn
  environment {
    variables = {
      SEOUL_HEALTH_URL  = var.seoul_health_url # ⚠️ 서울 prod ALB '직접' DNS (failover 도메인 아님)
      COORDINATOR_TABLE = aws_dynamodb_table.coordinator.name
      ALERT_TOPIC       = aws_sns_topic.approvals.arn
      ROUTE53_HC_ID     = var.route53_hc_id # 있으면 교차검증, 없으면 "" (생략)
    }
  }
}
