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
  desired_count          = 4
  task_cpu               = "512"
  task_memory            = "1024"
  ecs_security_group_ids = [module.sg.ecs_sg_id]
  alb_security_group_ids = [module.sg.alb_sg_id]
  spring_profile         = "prod"
  db_address             = module.rds.address
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  redis_endpoint         = module.elasticache.primary_endpoint
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
