# EKS 앱(파드)·ESO용 IRSA 역할 (prod)
# local.oidc_host, module.eks.oidc_provider_arn, data.aws_secretsmanager_secret.app, module.s3 는 기존 정의 재사용.

locals {
  extra_env = { for e in var.extra_environment : e.name => e.value }
}

# (1) 앱 파드용 — S3 권한 (ECS task role의 S3 정책 복제)
resource "aws_iam_role" "app" {
  name = "prod-eks-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:farmily-prod:farmily-app"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  name = "prod-eks-app-s3"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${module.s3.bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = module.s3.bucket_arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "app_bedrock" {
  count = var.ai_provider == "bedrock" ? 1 : 0
  name  = "prod-eks-app-bedrock"
  role  = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeAgent", "bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
      Resource = ["*"]
    }]
  })
}
# ============================================================================

# (2) ESO-reader용 — Secrets Manager 읽기
resource "aws_iam_role" "eso_reader" {
  name = "prod-eks-eso-reader-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:farmily-prod:eso-reader"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso_reader" {
  name = "prod-eks-eso-read-secrets"
  role = aws_iam_role.eso_reader.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [data.aws_secretsmanager_secret.app.arn, aws_secretsmanager_secret.app_infra.arn]
    }]
  })
}

resource "aws_secretsmanager_secret" "app_infra" {
  name = "farmily/prod/app-infra"
}

resource "aws_secretsmanager_secret_version" "app_infra" {
  secret_id = aws_secretsmanager_secret.app_infra.id
  secret_string = jsonencode({
    DB_URL                 = "jdbc:postgresql://${module.rds.address}:5432/${var.db_name}"
    DB_USERNAME            = var.db_username
    REDIS_HOST             = module.elasticache.primary_endpoint
    S3_BUCKET              = module.s3.bucket_id
    CDN_BASE_URL           = "https://${aws_cloudfront_distribution.images.domain_name}"
    AI_PROVIDER            = var.ai_provider
    AWS_REGION             = var.bedrock_region
    BEDROCK_AGENT_ID       = var.bedrock_agent_id
    BEDROCK_AGENT_ALIAS_ID = var.bedrock_agent_alias_id
    KAKAO_CLIENT_ID        = lookup(local.extra_env, "KAKAO_CLIENT_ID", "")
    KAKAO_REDIRECT_URI     = "https://farmily.info/oauth/kakao"
    PORTONE_IMP_CODE       = lookup(local.extra_env, "PORTONE_IMP_CODE", "")
    PORTONE_TEST_MODE      = "false"
  })
}
output "app_role_arn" { value = aws_iam_role.app.arn }
output "eso_reader_role_arn" { value = aws_iam_role.eso_reader.arn }
