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
  type        = string
  default     = ""
  description = "ACM ARN. enable_https = true 일 때 443 리스너에 부착."
}

variable "enable_https" {
  type        = bool
  default     = false
  description = "true면 443 리스너 + HTTP->HTTPS 301 활성화. count/for_each는 plan 시점에 알아야 하므로 ARN 대신 이 플래그로 제어."
}

variable "spring_profile" {
  type    = string
  default = "prod"
}

variable "db_address" {
  type = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "redis_endpoint" {
  type    = string
  default = ""
}

variable "extra_environment" {
  type        = list(object({ name = string, value = string }))
  default     = []
  description = "비민감 추가 env(공개 식별자·플래그: KAKAO_CLIENT_ID·*_REDIRECT_URI·*_TEST_MODE 등)만. 민감값은 app_secrets로."
}

variable "app_secrets" {
  type        = list(object({ name = string, valueFrom = string }))
  default     = []
  description = "Secrets Manager 참조 주입(secrets[]). DB_PASSWORD·JWT_SECRET·KAKAO_*·PORTONE_*·KMA_SERVICE_KEY·FCM_* 등 민감값은 평문 env가 아니라 이걸로."
}

variable "app_secret_arn_patterns" {
  type        = list(string)
  default     = []
  description = "execution role의 secretsmanager:GetSecretValue 허용 ARN(최소권한). 비면 정책 미생성."
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

variable "enable_container_insights" {
  type        = bool
  default     = false
  description = "true면 ECS Container Insights 활성화 (RunningTaskCount·per-task CPU/Mem 커스텀 메트릭 수집, CloudWatch 과금 발생). 기본 off = FinOps."
}

variable "max_count" {
  type        = number
  default     = 4
  description = "오토스케일링 최대 태스크 수"
}

variable "enable_eks_bluegreen" {
  type        = bool
  default     = false
}

variable "ecs_only_host" {
  type        = string
  default     = ""
}