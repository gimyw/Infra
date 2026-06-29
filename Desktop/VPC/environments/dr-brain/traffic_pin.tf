# Phase 6(복구) — traffic_pin : 사용자 트래픽을 도쿄에 고정/해제 (fence의 트래픽 층 짝, 수동)
# 서울 ALB health check 경로를 항상 404나는 경로로 바꿔(강제 unhealthy) Route53 failover가 도쿄로만
# 응답하게 한다. FIS 15분 자동복구로 서울이 살아나도 트래픽이 안 되돌아간다(auto-failback 차단).
# ⚠️ 자동화 금지 — 실전 failover 중에만. 회고 카드의 [트래픽 도쿄 고정] 버튼 또는 직접 invoke:
#   aws lambda invoke --region ap-northeast-1 --function-name dr-brain-traffic-pin \
#     --payload '{"action":"pin"}' --cli-binary-format raw-in-base64-out /dev/stdout

data "archive_file" "traffic_pin" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/traffic_pin"
  output_path = "${path.module}/build/traffic_pin.zip"
}
resource "aws_iam_role" "traffic_pin" {
  name               = "dr-brain-traffic-pin-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "traffic_pin_logs" {
  role       = aws_iam_role.traffic_pin.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "traffic_pin" {
  name = "traffic-pin-perms"
  role = aws_iam_role.traffic_pin.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:GetHealthCheck", "route53:UpdateHealthCheck"]
        Resource = "*" # 서울 ALB health check (Route53 HC ARN은 와일드카드)
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.coordinator.arn
      }
    ]
  })
}
resource "aws_lambda_function" "traffic_pin" {
  function_name    = "dr-brain-traffic-pin"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 30
  filename         = data.archive_file.traffic_pin.output_path
  source_code_hash = data.archive_file.traffic_pin.output_base64sha256
  role             = aws_iam_role.traffic_pin.arn
  environment {
    variables = {
      COORDINATOR_TABLE = aws_dynamodb_table.coordinator.name
      HEALTH_CHECK_ID   = var.seoul_health_check_id
    }
  }
}
