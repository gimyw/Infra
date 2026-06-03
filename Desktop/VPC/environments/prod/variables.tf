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


