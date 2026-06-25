# Grafana Tempo 트레이스 저장 — S3 백엔드 + IRSA. SA: monitoring:tempo
# 백엔드(Spring) OTel 자바에이전트 → Tempo(OTLP) → 이 버킷. (방법 A: 컬렉터 없이 앱 직결)

resource "aws_s3_bucket" "tempo_traces" {
  bucket = "farmily-tempo-traces"
}

# 트레이스는 단기 진단용 → 7일 후 만료(비용). Tempo compactor 보관(72h)과 별개의 S3 백스톱.
resource "aws_s3_bucket_lifecycle_configuration" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id
  rule {
    id     = "expire-traces"
    status = "Enabled"
    filter {}
    expiration { days = 7 }
  }
}

resource "aws_iam_role" "tempo" {
  name = "prod-eks-tempo-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
        "${local.oidc_host}:sub" = "system:serviceaccount:monitoring:tempo"
      } }
    }]
  })
}

resource "aws_iam_role_policy" "tempo" {
  name = "prod-eks-tempo-policy"
  role = aws_iam_role.tempo.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "TempoS3"
      Effect = "Allow"
      Action = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = [
        aws_s3_bucket.tempo_traces.arn,
        "${aws_s3_bucket.tempo_traces.arn}/*",
      ]
    }]
  })
}

output "tempo_role_arn" { value = aws_iam_role.tempo.arn }
