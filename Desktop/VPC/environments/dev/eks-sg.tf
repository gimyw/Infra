# ALB -> EKS 파드(8080) SG 규칙.
# eks 모듈에서 루트로 이동(모듈 순환 회피: sg가 eks 클러스터 SG를 참조 ↔ eks가 alb_sg 참조 → cycle).
# 대상 SG는 EKS가 자동 생성한 클러스터 SG라 별도 aws_security_group_rule 로 붙인다.
resource "aws_security_group_rule" "alb_to_eks_pods" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = module.sg.alb_sg_id
  description              = "ALB to EKS pods (app port 8080)"
}

# Jenkins EC2 -> EKS API 서버(443) 접근 허용
# terraform plan/apply 시 Helm provider가 EKS 프라이빗 엔드포인트에 연결 필요
# Jenkins EC2(10.0.10.250)는 동일 VPC 내 프라이빗 서브넷 → 클러스터 SG에 규칙 추가
data "aws_security_group" "jenkins" {
  name = "farmily-jenkins-sg"
}

resource "aws_security_group_rule" "jenkins_to_eks_api" {
  description              = "Jenkins TF runner to EKS API server (helm provider)"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.jenkins.id
  security_group_id        = module.eks.cluster_security_group_id
}
