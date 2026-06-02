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

  env                   = "dev"
  region                = var.region
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_a_cidr  = "10.0.1.0/24"
  public_subnet_c_cidr  = "10.0.2.0/24"
  private_subnet_a_cidr = "10.0.10.0/24"
  private_subnet_c_cidr = "10.0.11.0/24"
  enable_multi_nat      = false
  enable_vpn            = true
  vpn_server_cert_arn   = var.vpn_server_cert_arn
  vpn_client_cert_arn   = var.vpn_client_cert_arn
}

module "ecs" {
  source = "../../modules/ecs"

  env                    = "dev"
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  public_subnet_ids      = [module.vpc.public_subnet_a_id, module.vpc.public_subnet_c_id]
  private_subnet_ids     = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  container_image        = var.container_image
  desired_count          = 1
  ecs_security_group_ids = var.ecs_security_group_ids
  alb_security_group_ids = var.alb_security_group_ids
}

module "rds" {
  source = "../../modules/rds"

  env                = "dev"
  private_subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  security_group_ids = var.rds_security_group_ids
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  multi_az           = false
}

module "elasticache" {
  source = "../../modules/elasticache"

  env                = "dev"
  private_subnet_ids = [module.vpc.private_subnet_a_id, module.vpc.private_subnet_c_id]
  security_group_ids = var.redis_security_group_ids
  num_cache_clusters = 1
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  env              = "dev"
  ecs_cluster_name = "dev-cluster"
  ecs_service_name = "dev-app-service"
  rds_instance_id  = "dev-rds"
}
