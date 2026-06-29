# Phase 3 — Slack 승인 배관 : 승인 토큰 테이블 + slack 두 Lambda
# dr-1의 lambda_assume(iam.tf) · data.aws_caller_identity.me(data.tf)를 그대로 재사용.
# 두 Lambda 모두 표준 라이브러리만 쓰므로 VPC·의존성 zip 불필요.

# 긴 taskToken을 짧은 id로 가려 보관하는 테이블 (notify가 put, callback이 get/delete)
resource "aws_dynamodb_table" "tasktokens" {
  name         = "dr-brain-tasktokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }

  tags = { Name = "dr-brain-tasktokens" }
}

data "archive_file" "slack_notify" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/slack_notify"
  output_path = "${path.module}/build/slack_notify.zip"
}
data "archive_file" "slack_callback" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/slack_callback"
  output_path = "${path.module}/build/slack_callback.zip"
}

# Slack 시크릿(콘솔 예외로 사람이 등록): bot_token · signing_secret · channel.
# ARN 와일드카드(-*)라 시크릿이 아직 없어도 apply는 통과(런타임에만 읽힌다).
locals {
  slack_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:${data.aws_caller_identity.me.account_id}:secret:farmily/dr/slack-*"
}

# ── slack_notify : 카드 게시 + 토큰 저장 ─────────────────────
resource "aws_iam_role" "slack_notify" {
  name               = "dr-brain-slack-notify-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "slack_notify_logs" {
  role       = aws_iam_role.slack_notify.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "slack_notify" {
  name = "notify-perms"
  role = aws_iam_role.slack_notify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.slack_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.tasktokens.arn
      }
    ]
  })
}
resource "aws_lambda_function" "slack_notify" {
  function_name    = "dr-brain-slack-notify"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 15
  filename         = data.archive_file.slack_notify.output_path
  source_code_hash = data.archive_file.slack_notify.output_base64sha256
  role             = aws_iam_role.slack_notify.arn
  environment {
    variables = {
      SLACK_SECRET = "farmily/dr/slack"
      TOKENS_TABLE = aws_dynamodb_table.tasktokens.name
    }
  }
}

# ── slack_callback : 서명검증 + 흐름 재개 ───────────────────
resource "aws_iam_role" "slack_callback" {
  name               = "dr-brain-slack-callback-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "slack_callback_logs" {
  role       = aws_iam_role.slack_callback.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "slack_callback" {
  name = "callback-perms"
  role = aws_iam_role.slack_callback.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.slack_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.tasktokens.arn
      },
      {
        Effect   = "Allow"
        Action   = ["states:SendTaskSuccess", "states:SendTaskFailure"]
        Resource = "*"
      },
      {
        # 회고 카드의 복구 버튼(unfence/pin/unpin)이 누르면 콜백이 해당 Lambda를 직접 호출
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [aws_lambda_function.unfence.arn, aws_lambda_function.traffic_pin.arn]
      }
    ]
  })
}
resource "aws_lambda_function" "slack_callback" {
  function_name    = "dr-brain-slack-callback"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 10
  filename         = data.archive_file.slack_callback.output_path
  source_code_hash = data.archive_file.slack_callback.output_base64sha256
  role             = aws_iam_role.slack_callback.arn
  environment {
    variables = {
      SLACK_SECRET   = "farmily/dr/slack"
      TOKENS_TABLE   = aws_dynamodb_table.tasktokens.name
      UNFENCE_FN     = aws_lambda_function.unfence.function_name     # 회고 카드 복구 버튼용
      TRAFFIC_PIN_FN = aws_lambda_function.traffic_pin.function_name # 회고 카드 트래픽 버튼용
    }
  }
}
