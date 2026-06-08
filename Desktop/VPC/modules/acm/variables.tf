variable "domain_name" {
  type        = string
  description = "인증서 기본 도메인 (예: api.farmily.info 또는 farmily.info)"
}

variable "subject_alternative_names" {
  type        = list(string)
  default     = []
  description = "추가 도메인 (예: [\"www.farmily.info\"])"
}

variable "zone_id" {
  type        = string
  description = "DNS 검증 레코드를 생성할 Route53 호스팅 영역 ID"
}
