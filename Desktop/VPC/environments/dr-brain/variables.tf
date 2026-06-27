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
