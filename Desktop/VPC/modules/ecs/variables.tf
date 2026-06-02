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
