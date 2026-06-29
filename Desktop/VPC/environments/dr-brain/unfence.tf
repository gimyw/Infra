# Phase 6(복구) — unfence : fence가 백업한 prev_sgs로 prod-rds의 SG를 원복한다(수동 복구 도구)
# ⚠️ 자동화 금지 — 실전 promote 후 호출하면 split-brain. 드릴 종료 시 사람이 직접 invoke:
#   aws lambda invoke --region ap-northeast-1 --function-name dr-brain-unfence /dev/stdout

data "archive_file" "unfence" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/unfence"
  output_path = "${path.module}/build/unfence.zip"
}
resource "aws_iam_role" "unfence" {
  name               = "dr-brain-unfence-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "unfence_logs" {
  role       = aws_iam_role.unfence.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "unfence" {
  name = "unfence-perms"
  role = aws_iam_role.unfence.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.coordinator.arn
      },
      {
        Effect   = "Allow"
        Action   = ["rds:ModifyDBInstance"]
        Resource = "*" # 서울 prod-rds
      }
    ]
  })
}
resource "aws_lambda_function" "unfence" {
  function_name    = "dr-brain-unfence"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 60
  filename         = data.archive_file.unfence.output_path
  source_code_hash = data.archive_file.unfence.output_base64sha256
  role             = aws_iam_role.unfence.arn
  environment {
    variables = {
      COORDINATOR_TABLE = aws_dynamodb_table.coordinator.name
      PROD_RDS_ID       = "prod-rds"
    }
  }
}
