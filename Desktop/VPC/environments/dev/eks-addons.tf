locals {
    eks_exec = {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
    oidc_host   = replace(module.eks.oidc_provider_url, "https://", "")
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
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0" 
}

resource "aws_iam_policy" "lbc" {
    name           = "dev-eks-lbc-policy"
    policy         =  file("${path.module}/iam/lbc-iam-policy.json")
}

resource "aws_iam_role" "lbc" {
    name = "dev-eks-lbc-role"
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