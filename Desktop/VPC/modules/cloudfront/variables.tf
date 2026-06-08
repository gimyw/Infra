variable "env" {
  type = string
}

variable "s3_bucket_domain_name" {
  type = string
}

variable "aliases" {
  type        = list(string)
  default     = []
  description = "커스텀 도메인 목록 (예: [\"farmily.info\", \"www.farmily.info\"]). 빈 값이면 기본 cloudfront.net 도메인만 사용."
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "us-east-1 리전의 ACM 인증서 ARN. 빈 값이면 CloudFront 기본 인증서 사용."
}
