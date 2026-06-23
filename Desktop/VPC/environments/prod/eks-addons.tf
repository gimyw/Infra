locals {
  eks_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
  oidc_host = replace(module.eks.oidc_provider_url, "https://", "")
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)
  exec {
    api_version = local.eks_exec.api_version
    command     = local.eks_exec.command
    args        = local.eks_exec.args
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca)
    exec {
      api_version = local.eks_exec.api_version
      command     = local.eks_exec.command
      args        = local.eks_exec.args
    }
  }
}
# jenkins-tf-runner-prod가 EKS Helm/Kubernetes provider로 plan/apply하려면
# EKS access entry에 등록되어야 한다. (IAM 토큰은 발급되지만 K8s RBAC 인증 실패 방지)
# 최초 1회 수동 부트스트랩 후 import 필요 — 닭-달걀 문제
resource "aws_eks_access_entry" "jenkins_tf_runner" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::851957594139:role/farmily/irsa/jenkins-tf-runner-prod"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "jenkins_tf_runner" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::851957594139:role/farmily/irsa/jenkins-tf-runner-prod"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.jenkins_tf_runner]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0"
}

resource "aws_iam_policy" "lbc" {
  name   = "prod-eks-lbc-policy"
  policy = file("${path.module}/iam/lbc-iam-policy.json")
}

resource "aws_iam_role" "lbc" {
  name = "prod-eks-lbc-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}
//로드밸런서 컨트롤러
output "lbc_role_arn" {
  value = aws_iam_role.lbc.arn
}
