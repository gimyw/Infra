terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "aws" {
  region = var.region
}

# ==============================================================================
# VPC
# ==============================================================================
module "vpc" {
  source = "../../modules/vpc"

  env                   = "dr"
  region                = var.region
  vpc_cidr              = "10.2.0.0/16"
  public_subnet_a_cidr  = "10.2.1.0/24"
  public_subnet_c_cidr  = "10.2.2.0/24"
  private_subnet_a_cidr = "10.2.10.0/24"
  private_subnet_c_cidr = "10.2.11.0/24"
  enable_multi_nat      = false # DR cost optimization: single NAT
  enable_vpn            = false
}

# ==============================================================================
# Security Groups
# ==============================================================================
module "sg" {
  source = "../../modules/sg"

  env                   = "dr"
  vpc_id                = module.vpc.vpc_id
  enable_lambda_sg      = false
  enable_noti_lambda_sg = false
  eks_cluster_sg_id     = module.eks.cluster_security_group_id
}

# ==============================================================================
# EKS Cluster (Warm Standby - minimal)
# ==============================================================================
module "eks" {
  source = "../../modules/eks"

  env                = "dr"
  region             = var.region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  public_subnet_ids  = [module.vpc.public_subnet_a_id, module.vpc.public_subnet_c_id]

  cluster_version     = "1.35"
  node_instance_types = ["t3.medium"]
  node_desired_size   = 1 # Warm Standby: 최소 노드
  node_min_size       = 1
  node_max_size       = 6 # Failover 시 스케일아웃 허용
}

# ALB -> EKS 파드 인바운드 규칙
resource "aws_security_group_rule" "alb_to_eks_pods" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = module.sg.alb_sg_id
  description              = "ALB to EKS pods (app port 8080)"
}

# ==============================================================================
# ALB (DR 전용 - ECS 모듈 없이 직접 생성)
# ==============================================================================
resource "aws_lb" "dr" {
  name               = "dr-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.sg.alb_sg_id]
  subnets            = [module.vpc.public_subnet_a_id, module.vpc.public_subnet_c_id]

  tags = { Name = "dr-alb" }
}

resource "aws_lb_target_group" "eks" {
  name        = "dr-eks-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/api/v1/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "dr-eks-tg" }
}

# ACM for DR ALB (도쿄 리전)
resource "aws_acm_certificate" "dr_alb" {
  domain_name       = var.api_domain
  validation_method = "DNS"

  tags = { Name = "dr-alb-cert" }

  lifecycle { create_before_destroy = true }
}

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate_validation" "dr_alb" {
  certificate_arn = aws_acm_certificate.dr_alb.arn
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.dr.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.dr_alb.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks.arn
  }
}

# HTTP → HTTPS redirect
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.dr.arn
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

# ==============================================================================
# S3 (CRR 수신 버킷)
# ==============================================================================
resource "aws_s3_bucket" "dr_images" {
  bucket = "farmily-s3-bucket-dr"
  tags   = { Name = "farmily-s3-bucket-dr" }
}

resource "aws_s3_bucket_versioning" "dr_images" {
  bucket = aws_s3_bucket.dr_images.id
  versioning_configuration { status = "Enabled" }
}

# ==============================================================================
# RDS Cross-Region Read Replica
# ==============================================================================
resource "aws_db_subnet_group" "dr" {
  name       = "dr-db-subnet-group"
  subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]

  tags = { Name = "dr-db-subnet-group" }
}

resource "aws_db_instance" "dr_replica" {
  identifier          = "dr-rds"
  replicate_source_db = "arn:aws:rds:ap-northeast-2:851957594139:db:prod-rds"
  instance_class      = "db.t3.small"
  multi_az            = false

  db_subnet_group_name   = aws_db_subnet_group.dr.name
  vpc_security_group_ids = [module.sg.rds_sg_id]
  publicly_accessible    = false

  skip_final_snapshot = true
  apply_immediately   = true

  tags = { Name = "dr-rds-replica" }
}

# ==============================================================================
# Outputs
# ==============================================================================
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "alb_dns_name" {
  value = aws_lb.dr.dns_name
}

output "alb_zone_id" {
  value = aws_lb.dr.zone_id
}

output "alb_arn" {
  value = aws_lb.dr.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.eks.arn
}
