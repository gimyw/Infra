variable "env" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_a_cidr" {
  type = string
}

variable "public_subnet_c_cidr" {
  type = string
}

variable "private_subnet_a_cidr" {
  type = string
}

variable "private_subnet_c_cidr" {
  type = string
}

variable "private_db_subnet_a_cidr" {
  type    = string
  default = ""
  description = "DB tier private subnet AZ-a CIDR. Empty = not created."
}

variable "private_db_subnet_c_cidr" {
  type    = string
  default = ""
  description = "DB tier private subnet AZ-c CIDR. Empty = not created."
}

variable "enable_multi_nat" {
  type    = bool
  default = false
}

variable "enable_vpn" {
  type    = bool
  default = false
}

variable "vpn_server_cert_arn" {
  type    = string
  default = ""
}

variable "vpn_client_cert_arn" {
  type    = string
  default = ""
}
