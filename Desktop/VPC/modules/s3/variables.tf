variable "env" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "cors_allowed_origins" {
  type = list(string)
  description = "CORS 허용 origin (브라우저가 도는 곳). 예: http://localhost:3000"
}