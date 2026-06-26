resource "aws_prometheus_workspace" "ops" {
  alias = "farmily-ops"
  tags  = { Project = "farmily", Purpose = "ops-observability" }
}

resource "aws_iam_role" "amp_write" {
  name = "prod-eks-amp-write-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
        "${local.oidc_host}:sub" = "system:serviceaccount:monitoring:kube-prometheus-stack-prometheus"
      } }
    }]
  })
}

resource "aws_iam_role_policy" "amp_write" {
  name = "amp-remote-write"
  role = aws_iam_role.amp_write.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:RemoteWrite"]
      Resource = aws_prometheus_workspace.ops.arn
    }]
  })
}

output "amp_workspace_id" { value = aws_prometheus_workspace.ops.id }
output "amp_remote_write_url" { value = "${aws_prometheus_workspace.ops.prometheus_endpoint}api/v1/remote_write" }
output "amp_write_role_arn" { value = aws_iam_role.amp_write.arn }