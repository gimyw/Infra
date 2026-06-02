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

variable "ecs_security_group_ids" {
  type = list(string)
}

variable "alb_security_group_ids" {
  type = list(string)
}

variable "rds_security_group_ids" {
  type = list(string)
}

variable "redis_security_group_ids" {
  type = list(string)
}
