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

variable "s3_bucket_name" {
  type = string
}

variable "extra_environment" {
  type = list(object({ name = string, value = string}))
  default = []
  #plan 출력 시 값이 마스킹돼서 노출
  sensitive = true
}

variable "ai_provider" {
  type        = string
  default     = "mock"
  description = "AI 백엔드 선택 (mock | bedrock). bedrock으로 바꾸면 Task Role에 Bedrock 권한 자동 부여."
}

variable "bedrock_region" {
  type    = string
  default = "us-west-2"
}

variable "bedrock_agent_id" {
  type        = string
  default     = ""
  description = "Bedrock Agent ID (콘솔에서 생성 후 tfvars로 주입)."
}

variable "bedrock_agent_alias_id" {
  type        = string
  default     = ""
  description = "Bedrock Agent Alias ID."
}

# --- 도메인 / HTTPS ---
variable "domain_name" {
  type        = string
  default     = "farmily.info"
  description = "Route53 호스팅 영역(도메인). Route53에서 도메인 구매 시 자동 생성된 zone."
}

variable "web_domain" {
  type        = string
  default     = "farmily.info"
  description = "CloudFront(정적 웹) 기본 도메인"
}

variable "web_domain_aliases" {
  type        = list(string)
  default     = ["www.farmily.info"]
  description = "CloudFront 추가 도메인"
}

variable "api_domain" {
  type        = string
  default     = "api.farmily.info"
  description = "ALB(앱/API) 도메인"
}


