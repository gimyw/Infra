# Phase 7 — 검수 에이전트(audit_agent) : promote 직후 split-brain을 '스스로 조사'하는 읽기전용 AI 에이전트
# Bedrock Converse tool-use 루프(AgentCore 없이 Lambda 안에서). 도구는 전부 읽기전용 →
# bedrock:InvokeModel + dynamodb:GetItem(좌표) + rds:DescribeDBInstances 만. VPC 불필요(공개 API·health만).
# 분기(rule_verdict)는 핸들러의 결정론 _rule()이 정하고, AI는 조사·설명만 한다.
data "archive_file" "audit_agent" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/audit_agent"
  output_path = "${path.module}/build/audit_agent.zip"
}
resource "aws_iam_role" "audit_agent" {
  name               = "dr-brain-audit-agent-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "audit_agent_logs" {
  role       = aws_iam_role.audit_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "audit_agent" {
  name = "audit-agent-perms"
  role = aws_iam_role.audit_agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.coordinator.arn
      },
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances"] # dr-rds(도쿄)·prod-rds(서울) 둘 다 읽기
        Resource = "*"
      }
    ]
  })
}
resource "aws_lambda_function" "audit_agent" {
  function_name    = "dr-brain-audit-agent"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 120 # 도구 루프(최대 5턴) 여유
  filename         = data.archive_file.audit_agent.output_path
  source_code_hash = data.archive_file.audit_agent.output_base64sha256
  role             = aws_iam_role.audit_agent.arn
  environment {
    variables = {
      MODEL_ID          = var.bedrock_model_id
      COORDINATOR_TABLE = aws_dynamodb_table.coordinator.name
      SEOUL_HEALTH_URL  = var.seoul_health_url
      DR_RDS_ID         = "dr-rds"
      PROD_RDS_ID       = "prod-rds"
    }
  }
}
