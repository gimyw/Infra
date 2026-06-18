variable "env" {
    type = string
}

variable "region" {
    type    = string
    default = "ap-northeast-2"
}

variable "vpc_id" {
    type    = string
}

# 노드가 뜰 서브넷
variable "private_subnet_ids" {
    type = list(string)
}

# 컨트롤플레인 ENI 배치용 (private + public 함께 넘기면 무산)
variable "public_subnet_ids" {
  type    = list(string)
  default = []
}

variable "cluster_version" {
    type = string
    default = "1.35"
}

variable "endpoint_public_access" {
    type    = bool
    default = true
}

variable "node_instance_types" {
    type    = list(string)
    default = [ "t3.small" ]
}

variable "node_desired_size" {
    type    = number
    default = 1
}

variable "node_min_size" {
    type    = number
    default = 1
}

variable "node_max_size" {
    type    = number
    default = 3
}
