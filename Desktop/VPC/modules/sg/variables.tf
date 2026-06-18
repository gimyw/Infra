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

variable "enable_noti_lambda_sg" {
  type    = bool
  default = false
}

variable "agentcore_sg_id" {
  type        = string
  default     = ""
  description = "AgentCore SG id. 값이 있으면 RDS 5432 인바운드 소스로 추가(AgentCore->RDS). 빈 값이면 미추가."
}

variable "eks_cluster_sg_id" {
  type        = string
  default     = ""
  description = "EKS 클러스터 SG id. 값이 있으면 RDS(5432)·Redis(6379) 인바운드 소스로 추가(EKS 파드->RDS/Redis). 빈 값이면 미추가."
}
