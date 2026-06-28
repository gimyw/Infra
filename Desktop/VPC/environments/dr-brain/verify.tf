# Phase 4 — 검증(verify) : 승격된 dr-rds에 실제로 써보고 정상인지 확인
# 승격된 dr-rds(VPC 안)에 닿아야 하므로 dr_private 서브넷 + dr-rds SG에 붙인다(diagnose와 동일 배선).
# pg8000 의존 → 빌드 전 `pip install pg8000 -t lambdas/verify/` 필요(.gitignore로 vendored 미커밋).
data "archive_file" "verify" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/verify"
  output_path = "${path.module}/build/verify.zip"
}
resource "aws_iam_role" "verify" {
  name               = "dr-brain-verify-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "verify_logs" {
  role       = aws_iam_role.verify.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "verify_vpc" {
  role       = aws_iam_role.verify.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
resource "aws_iam_role_policy" "verify" {
  name = "verify-perms"
  role = aws_iam_role.verify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.promoted.arn,
        data.aws_secretsmanager_secret.app_infra.arn,
        data.aws_secretsmanager_secret.app.arn
      ]
    }]
  })
}
resource "aws_lambda_function" "verify" {
  function_name    = "dr-brain-verify"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 20
  filename         = data.archive_file.verify.output_path
  source_code_hash = data.archive_file.verify.output_base64sha256
  role             = aws_iam_role.verify.arn
  environment {
    variables = {
      PROMOTED_SECRET = aws_secretsmanager_secret.promoted.arn
      DB_SECRET       = "farmily/dr/app-infra"
      DB_APP_SECRET   = "farmily/dr/app" # 비번은 별도 시크릿(Phase 1 as-built과 동일)
    }
  }
  vpc_config {
    subnet_ids         = data.aws_subnets.dr_private.ids
    security_group_ids = [aws_security_group.diagnose_lambda.id]
  }
}
