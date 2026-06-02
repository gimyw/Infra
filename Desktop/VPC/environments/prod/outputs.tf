output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "redis_endpoint" {
  value = module.elasticache.primary_endpoint
}

output "cloudfront_domain" {
  value = module.cloudfront.distribution_domain_name
}
