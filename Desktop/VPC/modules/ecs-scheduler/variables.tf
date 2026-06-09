variable "env" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "start_schedule" {
  type    = string
  default = "cron(0 9 ? * MON-FRI *)"
}

variable "stop_schedule" {
  type    = string
  default = "cron(0 18 ? * MON-FRI *)"
}
