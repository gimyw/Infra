terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Route53에서 도메인 구매 시 자동 생성된 호스팅 영역 참조 (prod와 동일 zone)
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ALB(앱/API)용 인증서 - 서울 리전
module "acm_alb" {
  source = "../../modules/acm"

  domain_name = var.api_domain
  zone_id     = data.aws_route53_zone.main.zone_id
}

# 앱 시크릿(Secrets Manager) — 값이 아니라 ARN만 참조(평문 노출 없음). secrets[] 주입·정책에 사용.
data "aws_secretsmanager_secret" "app" {
  name = "farmily/dev/app"
}

locals {
  app_secret_keys = [
    "DB_PASSWORD", "JWT_SECRET", "KAKAO_CLIENT_SECRET", "KAKAO_ADMIN_KEY",
    "KMA_SERVICE_KEY", "PORTONE_API_KEY", "PORTONE_API_SECRET",
    "PORTONE_WEBHOOK_SECRET", "AUTH_DEV_MASTER_CODE", "FCM_SERVICE_ACCOUNT_JSON",
  ]
  app_secrets = [for k in local.app_secret_keys : {
    name      = k
    valueFrom = "${data.aws_secretsmanager_secret.app.arn}:${k}::"
  }]

  # 민감 키는 env에서 제외(secrets[]로만 주입) — tfvars 잔존값이 평문 env로 새거나 secrets와 중복되지 않게 방어
  app_environment = [
    for e in concat(var.extra_environment, [
      { name = "S3_BUCKET", value = module.s3.bucket_id },
      { name = "S3_REGION", value = var.region },
    ]) : e if !contains(local.app_secret_keys, e.name)
  ]
}

module "vpc" {
  source = "../../modules/vpc"

  env                   = "dev"
  region                = var.region
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_a_cidr  = "10.0.1.0/24"
  public_subnet_c_cidr  = "10.0.2.0/24"
  private_subnet_a_cidr = "10.0.10.0/24"
  private_subnet_c_cidr = "10.0.11.0/24"
  enable_multi_nat      = false
  enable_vpn            = false
}

module "sg" {
  source = "../../modules/sg"

  env    = "dev"
  vpc_id = module.vpc.vpc_id
}

module "ecs" {
  source = "../../modules/ecs"

  env                     = "dev"
  region                  = var.region
  vpc_id                  = module.vpc.vpc_id
  public_subnet_ids       = [module.vpc.public_subnet_a_id, module.vpc.public_subnet_c_id]
  private_subnet_ids      = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  container_image         = var.container_image
  desired_count           = 1
  max_count               = 2
  task_cpu                = "512"
  task_memory             = "1024"
  ecs_security_group_ids  = [module.sg.ecs_sg_id]
  alb_security_group_ids  = [module.sg.alb_sg_id]
  spring_profile          = "dev"
  enable_https            = true
  alb_certificate_arn     = module.acm_alb.certificate_arn
  db_address              = module.rds.address
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  redis_endpoint          = module.elasticache.primary_endpoint
  extra_environment       = local.app_environment
  app_secrets             = local.app_secrets
  app_secret_arn_patterns = [data.aws_secretsmanager_secret.app.arn]
  s3_bucket_arn           = module.s3.bucket_arn
}

module "rds" {
  source = "../../modules/rds"

  env                 = "dev"
  private_subnet_ids  = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  security_group_ids  = [module.sg.rds_sg_id]
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = var.db_password
  multi_az            = false
  monitoring_interval = 30
}

module "elasticache" {
  source = "../../modules/elasticache"

  env                = "dev"
  private_subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  security_group_ids = [module.sg.redis_sg_id]
  num_cache_clusters = 1
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  env              = "dev"
  ecs_cluster_name = "dev-cluster"
  ecs_service_name = "dev-app-service"
  rds_instance_id  = "dev-rds"
}

module "s3" {
  source = "../../modules/s3"

  env                  = "dev"
  bucket_name          = "farmily-dev-s3-bucket"
  cors_allowed_origins = ["http://localhost:3000", "https://farmily.info", "https://www.farmily.info"]
}

module "route53" {
  source = "../../modules/route53"

  zone_id = data.aws_route53_zone.main.zone_id

  # 앱/API -> ALB 직접 (dev는 CloudFront 미사용)
  alb_dns_name     = module.ecs.alb_dns_name
  alb_zone_id      = module.ecs.alb_zone_id
  alb_record_names = [var.api_domain]
}

module "ecs_scheduler" {
  source = "../../modules/ecs-scheduler"

  env              = "dev"
  region           = var.region
  ecs_cluster_name = "dev-cluster"
  ecs_service_name = "dev-app-service"
  start_schedule   = "cron(0 9 ? * MON-FRI *)"
  stop_schedule    = "cron(0 18 ? * MON-FRI *)"
}

module "eks" {
  source = "../../modules/eks"

  env                = "dev"
  region             = var.region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  public_subnet_ids  = [module.vpc.public_subnet_a_id, module.vpc.public_subnet_c_id]
  alb_sg_id          = module.sg.alb_sg_id

  //dev 영역의 EKS 노드 개수 및 버전
  cluster_version     = "1.35"
  node_instance_types = ["t3.medium"] //dev는 small
  node_desired_size   = 1
}
