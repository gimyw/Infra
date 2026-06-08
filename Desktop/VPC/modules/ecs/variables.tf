variable "env" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "task_cpu" {
  type    = string
  default = "256"
}

variable "task_memory" {
  type    = string
  default = "512"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "health_check_path" {
  type    = string
  default = "/api/v1/health"
}

variable "ecs_security_group_ids" {
  type = list(string)
}

variable "alb_security_group_ids" {
  type = list(string)
}

variable "alb_certificate_arn" {
  type = string
  default = ""
  description = "ACM ARN, 빈 값이면 HTTPS 미사용 (HTTP Only)"
}

variable "spring_profile" {
  type = string
  default = "prod"
}

variable "db_address" {
  type = string
}

variable "db_port" {
  type = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "db_username" { 
  type = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "redis_endpoint" {
  type = string
  default = ""
}

variable "extra_environment" {
  type = list(object({ name = string, value = string}))
  default = []
  description = "JWT_SECRET , KAKAO_*, PORTONE_* 등 추가 env 평문 주입"
}

variable "s3_bucket_arn" {
  type        = string
  description = "ECS Task가 접근할 S3 버킷 ARN (앱 파일 업로드용)"
}

variable "enable_bedrock" {
  type        = bool
  default     = false
  description = "Bedrock AI 기능 활성화 여부. true일 때만 Task Role에 Bedrock 정책 부여."
}

variable "bedrock_agent_resource_arns" {
  type        = list(string)
  default     = ["*"]
  description = "Bedrock InvokeAgent 허용 리소스 ARN 목록. 콘솔에서 Agent 만든 후 특정 ARN으로 좁히는 것 권장."
}

variable "enable_autoscaling" {
  type        = bool
  default     = true
  description = "오토스케일링 활성화 여부"
}

variable "max_count" {
  type        = number
  default     = 4
  description = "오토스케일링 최대 태스크 수"
}