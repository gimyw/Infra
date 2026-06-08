# 앱/API 도메인 -> ALB (A Alias)
resource "aws_route53_record" "alb" {
  for_each = toset(var.alb_record_names)

  zone_id = var.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# 정적 웹 도메인 -> CloudFront (A Alias)
resource "aws_route53_record" "cloudfront" {
  for_each = toset(var.cloudfront_record_names)

  zone_id = var.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2" # CloudFront 고정 hosted zone ID (전역 공통)
    evaluate_target_health = false
  }
}
