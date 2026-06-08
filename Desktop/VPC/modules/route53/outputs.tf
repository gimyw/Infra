output "alb_fqdns" {
  value = [for r in aws_route53_record.alb : r.fqdn]
}

output "cloudfront_fqdns" {
  value = [for r in aws_route53_record.cloudfront : r.fqdn]
}
