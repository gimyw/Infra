variable "zone_id" {
  type        = string
  description = "Route53 호스팅 영역 ID"
}

# --- ALB (앱/API) Alias ---
variable "alb_dns_name" {
  type        = string
  default     = ""
  description = "ALB DNS 이름"
}

variable "alb_zone_id" {
  type        = string
  default     = ""
  description = "ALB의 Route53 zone_id (Alias용)"
}

variable "alb_record_names" {
  type        = list(string)
  default     = []
  description = "ALB로 보낼 도메인 목록 (예: [\"api.farmily.info\"])"
}

# --- CloudFront (정적 웹) Alias ---
variable "cloudfront_domain_name" {
  type        = string
  default     = ""
  description = "CloudFront 배포 도메인 이름"
}

variable "cloudfront_record_names" {
  type        = list(string)
  default     = []
  description = "CloudFront로 보낼 도메인 목록 (예: [\"farmily.info\", \"www.farmily.info\"])"
}
