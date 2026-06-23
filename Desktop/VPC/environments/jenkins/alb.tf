# Jenkins ALB — GitHub 웹훅 수신용 공개 엔드포인트
# jenkins.farmily.info → ALB(공개) → Jenkins EC2(내부 10.0.10.250:8080)

locals {
  dev_public_subnet_a = "subnet-0e6c50470bd82b2f0"   # dev-public-subnet-a (ap-northeast-2a)
  dev_public_subnet_c = "subnet-0e84497444f496f84"   # dev-public-subnet-c (ap-northeast-2c)
}

data "aws_route53_zone" "main" {
  name = "farmily.info."
}

# ────────────────────────────────────────────────────────────────
# 1. ACM 인증서 (jenkins.farmily.info)
# ────────────────────────────────────────────────────────────────
resource "aws_acm_certificate" "jenkins" {
  domain_name       = "jenkins.farmily.info"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { project = "farmily", team = "urbanwork", purpose = "jenkins-alb-tls" }
}

resource "aws_route53_record" "jenkins_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.jenkins.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "jenkins" {
  certificate_arn         = aws_acm_certificate.jenkins.arn
  validation_record_fqdns = [for r in aws_route53_record.jenkins_cert_validation : r.fqdn]
}

# ────────────────────────────────────────────────────────────────
# 2. ALB SG — 인터넷에서 80/443 허용
# ────────────────────────────────────────────────────────────────
resource "aws_security_group" "jenkins_alb" {
  name        = "farmily-jenkins-alb-sg"
  description = "Jenkins ALB - 80/443 from internet"
  vpc_id      = local.dev_vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { project = "farmily", team = "urbanwork", purpose = "jenkins-alb" }
}

# Jenkins EC2 SG에 ALB → 8080 inbound 추가
# vpn.tf의 jenkins SG를 직접 수정하지 않고 rule로 분리
resource "aws_security_group_rule" "jenkins_from_alb" {
  type                     = "ingress"
  description              = "Jenkins UI from ALB"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.jenkins_alb.id
  security_group_id        = aws_security_group.jenkins.id
}

# ────────────────────────────────────────────────────────────────
# 3. ALB
# ────────────────────────────────────────────────────────────────
resource "aws_lb" "jenkins" {
  name               = "farmily-jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.jenkins_alb.id]
  subnets            = [local.dev_public_subnet_a, local.dev_public_subnet_c]

  tags = { project = "farmily", team = "urbanwork", purpose = "jenkins-webhook" }
}

# ────────────────────────────────────────────────────────────────
# 4. Target Group → Jenkins EC2 8080
# ────────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "jenkins" {
  name     = "farmily-jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = local.dev_vpc_id

  health_check {
    path                = "/login"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
  }

  tags = { project = "farmily", team = "urbanwork" }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins.id
  port             = 8080
}

# ────────────────────────────────────────────────────────────────
# 5. 리스너
# ────────────────────────────────────────────────────────────────
resource "aws_lb_listener" "jenkins_https" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.jenkins.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

resource "aws_lb_listener" "jenkins_http" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ────────────────────────────────────────────────────────────────
# 6. Route53 A 레코드 (jenkins.farmily.info → ALB)
# ────────────────────────────────────────────────────────────────
resource "aws_route53_record" "jenkins" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "jenkins.farmily.info"
  type    = "A"

  alias {
    name                   = aws_lb.jenkins.dns_name
    zone_id                = aws_lb.jenkins.zone_id
    evaluate_target_health = true
  }
}

output "jenkins_alb_dns" {
  value = aws_lb.jenkins.dns_name
}

output "jenkins_url" {
  value = "https://jenkins.farmily.info"
}
