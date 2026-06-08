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

# CloudFront용 ACM 인증서는 반드시 us-east-1 에 있어야 함
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Route53에서 도메인 구매 시 자동 생성된 호스팅 영역 참조 (새로 만들지 않음)
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

# CloudFront(정적 웹)용 인증서 - us-east-1
module "acm_cloudfront" {
  source = "../../modules/acm"
  providers = {
    aws = aws.us_east_1
  }

  domain_name               = var.web_domain
  subject_alternative_names = var.web_domain_aliases
  zone_id                   = data.aws_route53_zone.main.zone_id
}

locals {
  app_environment = concat(
    var.extra_environment,
    [
      { name = "S3_BUCKET",              value = module.s3.bucket_id },
      { name = "S3_REGION",              value = var.region },
      { name = "CDN_BASE_URL",           value = "https://${module.cloudfront.distribution_domain_name}" },
      { name = "AI_PROVIDER",            value = var.ai_provider },
      { name = "AWS_REGION",             value = var.bedrock_region },
      { name = "BEDROCK_AGENT_ID",       value = var.bedrock_agent_id },
      { name = "BEDROCK_AGENT_ALIAS_ID", value = var.bedrock_agent_alias_id },
    ]
  )
}

module "vpc" {
  source = "../../modules/vpc"

  env                   = "prod"
  region                = var.region
  vpc_cidr              = "10.1.0.0/16"
  public_subnet_a_cidr  = "10.1.1.0/24"
  public_subnet_c_cidr  = "10.1.2.0/24"
  private_subnet_a_cidr = "10.1.10.0/24"
  private_subnet_c_cidr = "10.1.11.0/24"
  enable_multi_nat      = true
  enable_vpn            = false
}

module "sg" {
  source = "../../modules/sg"

  env    = "prod"
  vpc_id = module.vpc.vpc_id
}

module "ecs" {
  source = "../../modules/ecs"

  env                    = "prod"
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  public_subnet_ids      = [module.vpc.public_subnet_a_id, module.vpc.public_subnet_c_id]
  private_subnet_ids     = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  container_image        = var.container_image
  desired_count          = 0
  max_count              = 8
  task_cpu               = "512"
  task_memory            = "1024"
  ecs_security_group_ids = [module.sg.ecs_sg_id]
  alb_security_group_ids = [module.sg.alb_sg_id]
  spring_profile         = "prod"
  alb_certificate_arn    = module.acm_alb.certificate_arn
  db_address             = module.rds.address
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  redis_endpoint         = module.elasticache.primary_endpoint
  extra_environment      = local.app_environment
  s3_bucket_arn          = module.s3.bucket_arn
  enable_bedrock         = var.ai_provider == "bedrock"
}

module "rds" {
  source = "../../modules/rds"

  env                = "prod"
  private_subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  security_group_ids = [module.sg.rds_sg_id]
  instance_class     = "db.t3.small"
  allocated_storage  = 50
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  multi_az           = true
}

module "elasticache" {
  source = "../../modules/elasticache"

  env                = "prod"
  private_subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  security_group_ids = [module.sg.redis_sg_id]
  node_type          = "cache.t3.small"
  num_cache_clusters = 2
}

module "s3" {
  source = "../../modules/s3"

  env                        = "prod"
  bucket_name                = var.s3_bucket_name
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  env                   = "prod"
  s3_bucket_domain_name = module.s3.bucket_domain_name
  aliases               = concat([var.web_domain], var.web_domain_aliases)
  acm_certificate_arn   = module.acm_cloudfront.certificate_arn
}

module "route53" {
  source = "../../modules/route53"

  zone_id = data.aws_route53_zone.main.zone_id

  # 앱/API -> ALB 직접
  alb_dns_name     = module.ecs.alb_dns_name
  alb_zone_id      = module.ecs.alb_zone_id
  alb_record_names = [var.api_domain]

  # 정적 웹 -> CloudFront
  cloudfront_domain_name  = module.cloudfront.distribution_domain_name
  cloudfront_record_names = concat([var.web_domain], var.web_domain_aliases)
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  env              = "prod"
  ecs_cluster_name = "prod-cluster"
  ecs_service_name = "prod-app-service"
  rds_instance_id  = "prod-rds"
}

resource "aws_s3_bucket_policy" "frontend_oac"{
  #bucket_id 오타 수정
  bucket = module.s3.bucket_id

  policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${module.s3.bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.distribution_arn
          }
        }
      }]
    })
}
