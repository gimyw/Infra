# Phase 4 — 전환(flip) : 좌표를 도쿄로 넘기고 새 쓰기 엔드포인트를 기록
resource "aws_secretsmanager_secret" "promoted" {
  name = "farmily/dr/promoted-db" # flip이 새 쓰기 엔드포인트를 여기에 기록(verify가 읽음)
}

data "archive_file" "flip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/flip_coordinator"
  output_path = "${path.module}/build/flip.zip"
}
resource "aws_iam_role" "flip" {
  name               = "dr-brain-flip-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "flip_logs" {
  role       = aws_iam_role.flip.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "flip" {
  name = "flip-perms"
  role = aws_iam_role.flip.id
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
        Action   = ["secretsmanager:PutSecretValue"]
        Resource = aws_secretsmanager_secret.promoted.arn
      }
      # 파드 재시작(ssm:SendCommand)은 아직 미배선(handler TODO) → 권한도 추가하지 않음.
    ]
  })
}
resource "aws_lambda_function" "flip" {
  function_name    = "dr-brain-flip"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 30
  filename         = data.archive_file.flip.output_path
  source_code_hash = data.archive_file.flip.output_base64sha256
  role             = aws_iam_role.flip.arn
  environment {
    variables = {
      COORDINATOR_TABLE = aws_dynamodb_table.coordinator.name
      PROMOTED_SECRET   = aws_secretsmanager_secret.promoted.arn
    }
  }
}
