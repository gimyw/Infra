resource "aws_iam_role" "karpenter_node" {
  name = "prod-eks-karpenter-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

locals {
  karpenter_node_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each   = toset(local.karpenter_node_policies)
  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

# 이 노드 역할을 EKS 클러스터가 인정하도록 access entry에 등록한다. (EKS API 인증)
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = "prod-eks"
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

# 카펜터(컨트롤러)가 EC2를 만들고 지울 권한 정의 (IRSA)
resource "aws_iam_role" "karpenter_controller" {
  name = "prod-eks-karpenter-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
        "${local.oidc_host}:sub" = "system:serviceaccount:karpenter:karpenter"
      } }
    }]
  })
}

# Karpenter 공식 컨트롤러 정책(JSON)을 파일로 붙인다. (iam/karpenter-controller-policy.json)
resource "aws_iam_policy" "karpenter_controller" {
  name   = "prod-eks-karpenter-policy"
  policy = file("${path.module}/iam/karpenter-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "prod-eks-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

# 중단 알림 큐: Spot 회수 2분 전 경고를 받아 Karpenter가 미리 파드를 다른 노드로 이전한다.
# On-Demand만 쓰면 선택이지만, Spot도 쓸 수 있으므로 둔다.
# EC2 Spot 중단/리밸런스/상태변경/Health 이벤트를 큐로 보낸다.
resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = {
    spot   = { source = ["aws.ec2"], detail-type = ["EC2 Spot Instance Interruption Warning"] }
    rebal  = { source = ["aws.ec2"], detail-type = ["EC2 Instance Rebalance Recommendation"] }
    health = { source = ["aws.health"], detail-type = ["AWS Health Event"] }
    state  = { source = ["aws.ec2"], detail-type = ["EC2 Instance State-change Notification"] }
  }
  name          = "prod-eks-karpenter-${each.key}"
  event_pattern = jsonencode({ source = each.value.source, "detail-type" = each.value["detail-type"] })
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = aws_cloudwatch_event_rule.karpenter
  rule     = each.value.name
  arn      = aws_sqs_queue.karpenter_interruption.arn
}

# Karpenter는 노드를 띄울 서브넷과 붙일 SG를 태그로 찾는다 (karpenter.sh/discovery = prod-eks).
# 프라이빗 서브넷 2개
resource "aws_ec2_tag" "subnet_discovery" {
  for_each    = toset([module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id])
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = "prod-eks"
}

# 클러스터 SG (노드가 붙을 SG)
resource "aws_ec2_tag" "sg_discovery" {
  resource_id = module.eks.cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = "prod-eks"
}
