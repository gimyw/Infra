# 코드 zip (pg8000 을 함께 담아 빌드한 폴더를 압축)
#   사전 1회: pip install pg8000 -t lambdas/diagnose/   (handler.py 옆에)
data "archive_file" "diagnose" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/diagnose"
  output_path = "${path.module}/build/diagnose.zip"
}
data "archive_file" "advisor" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/advisor"
  output_path = "${path.module}/build/advisor.zip"
}

# ── diagnose : VPC 안(replica 에 닿아야 함) ───────────────────
resource "aws_iam_role" "diagnose" {
  name               = "dr-brain-diagnose-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "diagnose_logs" {
  role       = aws_iam_role.diagnose.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "diagnose_vpc" {
  role       = aws_iam_role.diagnose.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
resource "aws_iam_role_policy" "diagnose_secret" {
  name = "read-db-secret"
  role = aws_iam_role.diagnose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        data.aws_secretsmanager_secret.app_infra.arn,
        data.aws_secretsmanager_secret.app.arn
      ]
    }]
  })
}
resource "aws_lambda_function" "diagnose" {
  function_name    = "dr-brain-diagnose"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 20
  filename         = data.archive_file.diagnose.output_path
  source_code_hash = data.archive_file.diagnose.output_base64sha256
  role             = aws_iam_role.diagnose.arn
  environment {
    variables = {
      DB_SECRET     = "farmily/dr/app-infra"
      DB_APP_SECRET = "farmily/dr/app"
    }
  }
  vpc_config {
    subnet_ids         = data.aws_subnets.dr_private.ids
    security_group_ids = [aws_security_group.diagnose_lambda.id]
  }
}

# ── advisor : VPC 불필요(Bedrock 호출만) ─────────────────────
resource "aws_iam_role" "advisor" {
  name               = "dr-brain-advisor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "advisor_logs" {
  role       = aws_iam_role.advisor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "advisor_bedrock" {
  name = "invoke-bedrock"
  role = aws_iam_role.advisor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "*" # 모델 ARN 으로 좁히면 더 좋음
    }]
  })
}
resource "aws_lambda_function" "advisor" {
  function_name    = "dr-brain-advisor"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 30
  filename         = data.archive_file.advisor.output_path
  source_code_hash = data.archive_file.advisor.output_base64sha256
  role             = aws_iam_role.advisor.arn
  environment {
    variables = {
      MODEL_ID = var.bedrock_model_id
    }
  }
}
