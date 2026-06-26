# CloudWatch Observability EKS 애드온 (도쿄 dr-eks) — prod 패턴 복제.
#   각 노드에 CloudWatch Agent(DaemonSet)=Container Insights 메트릭, Fluent Bit=컨테이너 로그.
#   DR 동기: 페일오버 시 도쿄 클러스터의 노드/파드/포화도를 DR 대시보드(④·⑤)에서 보기 위함.
# IRSA SA: amazon-cloudwatch:cloudwatch-agent (애드온이 이 SA로 권한을 받음)

resource "aws_iam_role" "cloudwatch_agent" {
  name = "dr-eks-cloudwatch-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
        "${local.oidc_host}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
      } }
    }]
  })
}

# 메트릭·로그 전부 CloudWatchAgentServerPolicy 하나로 충분.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# 애드온 설치 — Container Insights + Fluent Bit.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  service_account_role_arn    = aws_iam_role.cloudwatch_agent.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

output "dr_cloudwatch_agent_role_arn" { value = aws_iam_role.cloudwatch_agent.arn }
