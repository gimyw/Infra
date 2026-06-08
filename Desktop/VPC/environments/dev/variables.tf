variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "container_image" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "extra_environment" {
  type = list(object({ name = string, value = string}))
  default = []
  #plan 출력 시 값이 마스킹돼서 노출
  sensitive = true
}

# --- 도메인 / HTTPS ---
variable "domain_name" {
  type        = string
  default     = "farmily.info"
  description = "Route53 호스팅 영역(도메인). prod와 동일한 zone 사용."
}

variable "api_domain" {
  type        = string
  default     = "api.dev.farmily.info"
  description = "dev ALB(앱/API) 도메인"
}