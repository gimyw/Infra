# Phase 4 — 승격(promote) : 도쿄 replica를 주 DB로 (비가역)
# arm_promote 게이트는 람다 안에서 한 번 더 확인한다. 완료 대기는 Step Functions가 폴링.
data "archive_file" "promote" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/promote"
  output_path = "${path.module}/build/promote.zip"
}
resource "aws_iam_role" "promote" {
  name               = "dr-brain-promote-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "promote_logs" {
  role       = aws_iam_role.promote.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "promote" {
  name = "promote-perms"
  role = aws_iam_role.promote.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds:PromoteReadReplica", "rds:DescribeDBInstances"]
      Resource = "*"
    }]
  })
}
resource "aws_lambda_function" "promote" {
  function_name    = "dr-brain-promote"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 30
  filename         = data.archive_file.promote.output_path
  source_code_hash = data.archive_file.promote.output_base64sha256
  role             = aws_iam_role.promote.arn
  environment {
    variables = {
      DR_RDS_ID = "dr-rds"
    }
  }
}
