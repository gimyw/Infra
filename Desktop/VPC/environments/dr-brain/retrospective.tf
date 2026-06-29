# Phase 5 — 회고(retrospective) : 실행 히스토리 → 한국어 RTO/RPO 보고서 → S3
# Bedrock만 부르고 실행 히스토리만 읽으니 VPC 불필요. 보고서는 전용 버킷에 쌓는다(게임데이마다 누적).
resource "aws_s3_bucket" "reports" {
  bucket = "dr-brain-retro-${data.aws_caller_identity.me.account_id}"
  tags   = { Name = "dr-brain-retro" }
}

# 보고서에 DB 상태가 담기므로 공개 접근은 전부 차단
resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "retrospective" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/retrospective"
  output_path = "${path.module}/build/retrospective.zip"
}
resource "aws_iam_role" "retrospective" {
  name               = "dr-brain-retrospective-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "retrospective_logs" {
  role       = aws_iam_role.retrospective.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "retrospective" {
  name = "retro-perms"
  role = aws_iam_role.retrospective.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["states:GetExecutionHistory"], Resource = "*" },
      { Effect = "Allow", Action = ["bedrock:InvokeModel"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.reports.arn}/*" },
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = local.slack_secret_arn } # Slack 게시
    ]
  })
}
resource "aws_lambda_function" "retrospective" {
  function_name    = "dr-brain-retrospective"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 60
  filename         = data.archive_file.retrospective.output_path
  source_code_hash = data.archive_file.retrospective.output_base64sha256
  role             = aws_iam_role.retrospective.arn
  environment {
    variables = {
      MODEL_ID      = var.bedrock_model_id
      REPORT_BUCKET = aws_s3_bucket.reports.bucket
      SLACK_SECRET  = "farmily/dr/slack" # 회고를 Slack에도 게시(없으면 skip)
    }
  }
}
