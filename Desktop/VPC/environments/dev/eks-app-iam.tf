# EKS 앱(파드)·ESO용 IRSA 역할 (Phase 4)
# local.oidc_host, module.eks.oidc_provider_arn, data.aws_secretsmanager_secret.app, module.s3 는 기존 정의 재사용.

# (1) 앱 파드용 — S3 권한 (ECS task role의 S3 정책 복제)
resource "aws_iam_role" "app" {
  name = "dev-eks-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:farmily-dev:farmily-app"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  name = "dev-eks-app-s3"
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

# (2) ESO-reader용 — Secrets Manager 읽기
resource "aws_iam_role" "eso_reader" {
  name = "dev-eks-eso-reader-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:farmily-dev:eso-reader"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso_reader" {
  name = "dev-eks-eso-read-secrets"
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
  name = "farmily/dev/app-infra"
}

resource "aws_secretsmanager_secret_version" "app_infra" {
  secret_id = aws_secretsmanager_secret.app_infra.id
  secret_string = jsonencode({
    DB_URL      = "jdbc:postgresql://${module.rds.address}:5432/${var.db_name}"
    DB_USERNAME = var.db_username
    REDIS_HOST  = module.elasticache.primary_endpoint
    S3_BUCKET   = module.s3.bucket_id
  })

  lifecycle {
    # AWS provider v5.x secret_string_wo 속성 충돌로 perpetual replace 발생 방지
    ignore_changes = [secret_string]
  }
}
output "app_role_arn" { value = aws_iam_role.app.arn }
output "eso_reader_role_arn" { value = aws_iam_role.eso_reader.arn }
