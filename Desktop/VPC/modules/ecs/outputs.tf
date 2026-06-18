output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "alb_zone_id" {
  value = aws_lb.main.zone_id
}

output "eks_target_group_arn" {
  value = var.enable_eks_bluegreen ? aws_lb_target_group.eks[0].arn : null
}