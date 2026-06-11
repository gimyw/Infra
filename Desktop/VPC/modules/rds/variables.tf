variable "env" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "engine_version" {
  type    = string
  default = "18.3"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
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

variable "multi_az" {
  type    = bool
  default = false
}

variable "monitoring_interval" {
  type        = number
  default     = 0
  description = "Enhanced Monitoring 수집 간격(초). 0이면 비활성. 허용값: 0, 1, 5, 10, 15, 30, 60"
}

variable "enable_read_replica" {
  type    = bool
  default = false
}

variable "replica_instance_class" {
  type    = string
  default = "db.t3.small"
}
