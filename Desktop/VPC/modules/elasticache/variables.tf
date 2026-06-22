variable "env" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "num_cache_clusters" {
  type    = number
  default = 1
}

variable "engine_version" {
  type    = string
  default = "7.0"
}

variable "transit_encryption_enabled" {
  type    = bool
  default = false
}

variable "transit_encryption_mode" {
  type    = string
  default = "preferred"
}
