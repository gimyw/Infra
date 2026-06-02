variable "env" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "cloudfront_distribution_arn" {
  type    = string
  default = ""
}
