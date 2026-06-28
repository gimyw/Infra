# Phase 3 — Slack의 노크를 받는 문 (Lambda Function URL)
# 엔드포인트가 /slack 콜백 하나뿐이라 API Gateway 대신 Function URL이 가장 단순(리소스 4개 → 1개).
# 나중에 WAF·커스텀 도메인이 필요하면 앞단만 API Gateway로 바꾼다 — 콜백 코드는 그대로(둘 다 v2.0 이벤트).
resource "aws_lambda_function_url" "slack" {
  function_name      = aws_lambda_function.slack_callback.function_name
  authorization_type = "NONE" # 공개 — 인증은 Slack 서명검증으로 Lambda 안에서 한다
}

# AuthType=NONE이면 이 권한이 있어야 외부에서 URL 호출이 된다
resource "aws_lambda_permission" "slack_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.slack_callback.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# apply 후 이 URL을 Slack 앱 ▸ Interactivity ▸ Request URL에 채운다.
output "slack_callback_url" {
  value = aws_lambda_function_url.slack.function_url
}
