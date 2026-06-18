output "cluster_name" {
    value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
    value = aws_eks_cluster.this.endpoint
}

//EKS가 만든 클러스터 SG
output "cluster_ca" {
    value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id"{
    value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn"{
    value = aws_iam_openid_connect_provider.this.arn
}
output "oidc_provider_url"{
    value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_role_arn"{
    value = aws_iam_role.node.arn
}