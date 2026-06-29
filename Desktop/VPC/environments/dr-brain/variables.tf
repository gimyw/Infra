variable "bedrock_model_id" {
  description = "도쿄에서 호출할 Bedrock 추론 프로파일 ID (aws bedrock list-inference-profiles --region ap-northeast-1)"
  type        = string
}

# ── Phase 2 (detect_canary) ──────────────────────────────────
variable "seoul_health_url" {
  description = "서울 prod ALB의 '직접' DNS health 엔드포인트. ⚠️ failover 도메인(api.farmily.info) 금지 — 서울이 죽으면 도쿄로 넘어가 오판한다. 직접 DNS 확인: aws elbv2 describe-load-balancers --region ap-northeast-2"
  type        = string
}

variable "route53_hc_id" {
  description = "교차검증용 Route53 health check id (us-east-1 지표). 없으면 빈 문자열 — health probe 단일 신호로 동작."
  type        = string
  default     = ""
}

# ── Phase 6(복구) traffic_pin ────────────────────────────────
variable "seoul_health_check_id" {
  description = "서울 ALB Route53 health check id (api.farmily.info failover의 PRIMARY 레코드). traffic_pin의 pin이 이 health check 경로를 실패 경로로 바꿔 강제 unhealthy로 만들어 트래픽을 도쿄에 묶는다. 실측: aws route53 list-health-checks (예: 5ffe143a-c2bd-4711-a262-8611e81682cb). 미설정 시 빈 문자열(pin/unpin 호출 시에만 필요)."
  type        = string
  default     = ""
}
