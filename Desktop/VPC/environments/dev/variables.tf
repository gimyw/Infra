variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "container_image" {
  type = string
}

variable "vpn_server_cert_arn" {
  type = string
}

variable "vpn_client_cert_arn" {
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
