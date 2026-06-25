# CloudWatch Observability EKS 애드온 — 관측 평면을 클러스터 밖(CloudWatch)으로.
#   각 노드에 CloudWatch Agent(DaemonSet)=Container Insights 메트릭, Fluent Bit=컨테이너 로그,
#   Application Signals(ADOT 자동주입)=앱 트레이스. AgentCore(CloudWatch GenAI)와 단일 외부 평면.
#   DR 동기: 클러스터가 죽어도 관측은 CloudWatch(AWS 관리형)에 살아있다.
# IRSA SA: amazon-cloudwatch:cloudwatch-agent (애드온이 이 SA로 권한을 받음)

resource "aws_iam_role" "cloudwatch_agent" {
  name = "prod-eks-cloudwatch-agent-role"
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

# 메트릭·로그·트레이스(X-Ray) 전부 CloudWatchAgentServerPolicy 하나로 충분.
# (이 정책이 xray:PutTraceSegments·PutTelemetryRecords·GetSampling* 를 이미 포함 → 별도 X-Ray 정책 불필요)
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# 애드온 설치 — Container Insights + Application Signals(v5.0.0+ 기본 활성) + Fluent Bit.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  service_account_role_arn    = aws_iam_role.cloudwatch_agent.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

output "cloudwatch_agent_role_arn" { value = aws_iam_role.cloudwatch_agent.arn }
