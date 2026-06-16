# REGIONAL web ACL — ALB(L7) 보호. default=Allow, 룰에 걸리면 Block.
# 룰 우선순위(priority): 숫자 작을수록 먼저 평가, 첫 매치에서 action 확정.
#   p5  rate-limit-auth   : 로그인 경로 brute-force (scope-down)
#   p10 rate-limit-global : 전역 HTTP flood
#   (p20~p40 AWS managed 룰은 별도 단계에서 추가)
resource "aws_wafv2_web_acl" "alb" {
  name        = "${var.env}-alb-waf"
  description = "Farmily ${var.env} ALB L7 protection - rate-limit + AWS managed rules"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # ── priority 5: 인증경로 brute-force ──
  # scope_down_statement 로 /api/v1/auth/* 요청만 카운트 대상으로 좁힘.
  # 같은 IP가 해당 경로에 5분간 rate_limit_auth 회 초과 시 Block.
  rule {
    name     = "rate-limit-auth"
    priority = 5
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_auth
        aggregate_key_type = "IP"
        scope_down_statement {
          byte_match_statement {
            search_string         = "/api/v1/auth/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.env}-rate-auth"
    }
  }

  # ── priority 10: 전역 HTTP flood ──
  # 경로 무관, 같은 IP가 5분간 rate_limit_global 회 초과 시 Block.
  rule {
    name     = "rate-limit-global"
    priority = 10
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_global
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.env}-rate-global"
    }
  }

  # ── priority 20: Amazon IP 평판 (스캐너/봇넷/악성 IP — PHP probe 발신지 차단) ──
  # managed rule group 은 action 대신 override_action 으로 통제. none{} = 그룹 기본(block) 따름.
  rule {
    name     = "aws-ip-reputation"
    priority = 20
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.env}-ip-reputation"
    }
  }

  # ── priority 30: 알려진 악성 입력(RCE/exploit 페이로드, Log4Shell 등) ──
  rule {
    name     = "aws-known-bad-inputs"
    priority = 30
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.env}-known-bad-inputs"
    }
  }

  # ── priority 40: 일반 OWASP(SQLi/XSS/LFI) — 오탐 위험 있어 초기 Count(관측)로 시작 ──
  # common_rule_action 변수로 count(관측만) <-> none(=block) 토글. 검증 후 none 으로 승격.
  rule {
    name     = "aws-common"
    priority = 40
    override_action {
      dynamic "count" {
        for_each = var.common_rule_action == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = var.common_rule_action == "none" ? [1] : []
        content {}
      }
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        # 카카오 로그인 경로는 CommonRuleSet 평가에서 제외
        # 해당 경로는 rate-limit-auth + known-bad-inputs + ip-reputation 으로 계속 보호
        scope_down_statement {
          not_statement {
            statement {
              byte_match_statement {
                search_string         = "/api/v1/auth/kakao"
                positional_constraint = "STARTS_WITH"
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.env}-common"
    }
  }

  # web ACL 전체 메트릭/샘플
  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.env}-alb-waf"
  }
}

# ── web ACL <-> ALB 연결 ──
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}

# ── 로깅: CloudWatch Logs ──
# ⚠️ WAF 로깅 대상 log group 이름은 반드시 "aws-waf-logs-" 프리픽스여야 함(AWS 강제).
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.env}-alb"
  retention_in_days = var.log_retention_days
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.alb.arn

  # 인증 헤더는 로그에서 마스킹(시크릿 보호)
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}
