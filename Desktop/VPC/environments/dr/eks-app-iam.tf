# DR 앱 파드와 External Secrets Operator용 IRSA 역할.

resource "aws_secretsmanager_secret" "app" {
  name = "farmily/dr/app"
}

resource "aws_secretsmanager_secret" "app_infra" {
  name = "farmily/dr/app-infra"
}

resource "aws_secretsmanager_secret_version" "app_infra" {
  secret_id = aws_secretsmanager_secret.app_infra.id
  secret_string = jsonencode({
    DB_HOST    = aws_db_instance.dr_replica.address
    DB_PORT    = "5432"
    S3_BUCKET  = aws_s3_bucket.dr_images.id
    S3_REGION  = var.region
    AWS_REGION = var.region
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_iam_role" "app" {
  name = "dr-eks-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:farmily-dr:farmily-app"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  name = "dr-eks-app-s3"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.dr_images.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.dr_images.arn
      },
    ]
  })
}

resource "aws_iam_role" "eso_reader" {
  name = "dr-eks-eso-reader-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:farmily-dr:eso-reader"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso_reader" {
  name = "dr-eks-eso-read-secrets"
  role = aws_iam_role.eso_reader.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [aws_secretsmanager_secret.app.arn, aws_secretsmanager_secret.app_infra.arn]
    }]
  })
}

output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "eso_reader_role_arn" {
  value = aws_iam_role.eso_reader.arn
}
