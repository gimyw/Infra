# Phase 3 — Slack의 노크를 받는 문 (API Gateway HTTP API)
# 원래는 Function URL이 가장 단순했지만(리소스 1개), 이 계정(부트캠프 조직 rapa)이
# 공개 Lambda Function URL(AuthType=NONE)을 SCP/RCP로 차단한다 — 함수 리소스 정책으로
# 공개를 허용해도 익명 호출은 403 Forbidden. AWS→Slack(카드 게시)은 되는데 Slack→AWS
# (인바운드 콜백)가 막힘. HTTP API의 공개 엔드포인트는 lambda:InvokeFunctionUrl SCP
# 대상이 아니라 우회로가 된다. 콜백 코드는 그대로 — 둘 다 payload v2.0 이벤트.

resource "aws_apigatewayv2_api" "slack" {
  name          = "dr-brain-slack-callback"
  protocol_type = "HTTP"
  # CORS 불필요 — Slack→엔드포인트는 서버-투-서버(브라우저 프리플라이트 없음).
}

# Lambda 프록시 통합. payload v2.0 → event.body/isBase64Encoded/headers 형태로 전달(핸들러 무수정).
resource "aws_apigatewayv2_integration" "slack" {
  api_id                 = aws_apigatewayv2_api.slack.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.slack_callback.invoke_arn
  payload_format_version = "2.0"
  integration_method     = "POST" # Lambda 호출용(클라이언트 메서드 아님)
}

# $default 캐치올 라우트 — Slack에 붙여넣은 URL의 경로가 무엇이든 받는다(경로 불일치 404 방지).
resource "aws_apigatewayv2_route" "slack" {
  api_id    = aws_apigatewayv2_api.slack.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.slack.id}"
}

# $default 스테이지 + auto_deploy → 스테이지 경로 없는 깔끔한 URL, 변경 시 자동 배포.
# 액세스 로그는 최소 구성 위해 생략(추가 IAM 불필요 — Lambda 자체 로그는 기존 역할로 남는다).
resource "aws_apigatewayv2_stage" "slack" {
  api_id      = aws_apigatewayv2_api.slack.id
  name        = "$default"
  auto_deploy = true
}

# HTTP API가 Lambda를 호출할 수 있게 허용. source_arn = execution_arn + "/*/*"
# (앞 * = 스테이지, 뒤 * = route_key) — $default 라우트/스테이지를 모두 포함한다.
resource "aws_lambda_permission" "slack_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_callback.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.slack.execution_arn}/*/*"
}

# apply 후 이 URL을 Slack 앱 ▸ Interactivity ▸ Request URL에 채운다.
# $default 스테이지라 invoke_url이 곧 호출 URL(스테이지 경로 접미사 없음).
output "slack_callback_url" {
  value = aws_apigatewayv2_stage.slack.invoke_url
}
