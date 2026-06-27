# 이미 있는 dr 리소스는 '참조'만 한다 (재선언 금지)
data "aws_caller_identity" "me" {}
data "aws_region" "tokyo" {}

# 도쿄 DR VPC (modules/vpc: Name = "${env}-vpc")
data "aws_vpc" "dr" {
  filter {
    name   = "tag:Name"
    values = ["dr-vpc"]
  }
}

# DR private subnet 2개 (modules/vpc: "${env}-private-subnet-{a,c}")
data "aws_subnets" "dr_private" {
  filter {
    name   = "tag:Name"
    values = ["dr-private-subnet-a", "dr-private-subnet-c"]
  }
}

# dr-rds 의 보안그룹 (modules/sg: Name = "${env}-rds-sg")
data "aws_security_group" "dr_rds" {
  tags = { Name = "dr-rds-sg" }
}

# diagnose 가 읽는 시크릿 2개
data "aws_secretsmanager_secret" "app_infra" {
  name = "farmily/dr/app-infra" # DB_HOST, DB_PORT, DB_USER(farmilyadmin), DB_NAME
}
data "aws_secretsmanager_secret" "app" {
  name = "farmily/dr/app" # DB_PASSWORD
}
