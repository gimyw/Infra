output "web_acl_arn" {
  description = "web ACL ARN (다른 리소스 연결·참조용)"
  value       = aws_wafv2_web_acl.alb.arn
}

output "web_acl_id" {
  value = aws_wafv2_web_acl.alb.id
}

output "log_group_name" {
  description = "WAF 로그 CloudWatch log group 이름"
  value       = aws_cloudwatch_log_group.waf.name
}
