#젠킨스 빌드 파드 IRSA, Service Account -> jenkins-build:jenkis-agent
## terraform 권한은 직접 안 갖고, 기존 jenkins-tf-runner-{dev,prod}를 assume(체인 재사용)
resource "aws_iam_role" "jenkins_tf" {
    name = "prod-eks-jenkins-tf-role"
    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = module.eks.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = { StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:jenkins-build:jenkins-agent"
        } }
      }]
    })
  }
  resource "aws_iam_role_policy" "jenkins_tf_assume" {
    name = "prod-eks-jenkins-tf-assume"
    role = aws_iam_role.jenkins_tf.id
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "AssumeTfRunners"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::851957594139:role/farmily/irsa/jenkins-tf-runner-dev",
          "arn:aws:iam::851957594139:role/farmily/irsa/jenkins-tf-runner-prod",
        ]
      }]
    })
  }

output "jenkins_tf_role_arn" {
  value = aws_iam_role.jenkins_tf.arn
}