# WAF 모듈 입력값
# - 환경(env)·보호대상 ALB ARN은 필수, 나머지는 안전한 기본값 제공
# - rate 한도는 변수화: 초기엔 넉넉히(Count 관측) → 로그 보고 조이기 위함

variable "env" {
  description = "환경 식별자 (prod | dev). 리소스 이름 프리픽스로 사용"
  type        = string
}

variable "alb_arn" {
  description = "WAF를 연결할 ALB의 ARN (예: module.ecs.alb_arn)"
  type        = string
}

variable "rate_limit_global" {
  description = "전역 rate-based 한도 — 같은 IP가 5분 안에 이 횟수를 넘기면 차단 (AWS SRT 권장 예시값 2000)"
  type        = number
  default     = 2000
}

variable "rate_limit_auth" {
  description = "인증경로(/api/v1/auth/*) rate-based 한도 — brute-force 방어. 시작값 100, 로그 보고 10~50으로 조임"
  type        = number
  default     = 100
}

variable "common_rule_action" {
  description = "CommonRuleSet(SQLi/XSS) override action — 초기 count(관측만), 오탐 검증 후 none(=차단)으로 승격"
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "none"], var.common_rule_action)
    error_message = "common_rule_action 은 \"count\" 또는 \"none\" 이어야 합니다."
  }
}

variable "log_retention_days" {
  description = "WAF 로그 CloudWatch 보존 일수"
  type        = number
  default     = 30
}
