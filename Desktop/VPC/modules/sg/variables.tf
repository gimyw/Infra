variable "env" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "enable_lambda_sg" {
  type    = bool
  default = false
}
