# Phase 4 — 차단(fence) : 구 서울이 더는 쓰기를 못 하게 막는다
# provider alias "seoul"(versions.tf)로 서울 prod VPC에 빈 fence-sg를 미리 만들어 두고,
# fence 람다가 arm_promote=true일 때만 prod-rds의 SG를 이걸로 통째 교체한다.

# 서울 prod VPC 참조 (modules/vpc 의 "${env}-vpc" → prod-vpc)
data "aws_vpc" "prod_seoul" {
  provider = aws.seoul
  tags     = { Name = "prod-vpc" }
}

# 빈 보안그룹(ingress 없음) — fence 때 prod-rds 의 SG를 이걸로 교체. 런타임에 만들 수 없으니 미리 둔다.
resource "aws_security_group" "fence" {
  provider    = aws.seoul
  name        = "dr-brain-fence-sg"
  description = "DR fence - empty SG to cut writes to old Seoul primary"
  vpc_id      = data.aws_vpc.prod_seoul.id

  tags = { Name = "dr-brain-fence-sg" }
}

data "archive_file" "fence" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/fence"
  output_path = "${path.module}/build/fence.zip"
}
resource "aws_iam_role" "fence" {
  name               = "dr-brain-fence-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json # iam.tf
}
resource "aws_iam_role_policy_attachment" "fence_logs" {
  role       = aws_iam_role.fence.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "fence" {
  name = "fence-perms"
  role = aws_iam_role.fence.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.coordinator.arn
      },
      {
        Effect   = "Allow"
        Action   = ["rds:ModifyDBInstance"]
        Resource = "*" # 서울 prod-rds
      }
    ]
  })
}
resource "aws_lambda_function" "fence" {
  function_name    = "dr-brain-fence"
  runtime          = "python3.12"
  handler          = "handler.handler"
  timeout          = 60
  filename         = data.archive_file.fence.output_path
  source_code_hash = data.archive_file.fence.output_base64sha256
  role             = aws_iam_role.fence.arn
  environment {
    variables = {
      COORDINATOR_TABLE = aws_dynamodb_table.coordinator.name
      FENCE_SG_ID       = aws_security_group.fence.id
      PROD_RDS_ID       = "prod-rds"
      # 서울 비번은 공유 시크릿(farmily/prod/app)뿐 + 로테이션 람다 없음 → 로테이션 생략, 차단은 SG 교체로.
      SEOUL_DB_SECRET = ""
    }
  }
}
