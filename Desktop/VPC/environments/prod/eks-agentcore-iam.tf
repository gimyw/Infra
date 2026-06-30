# AgentCore IRSA — ECS farmily-agentcore-task-role 권한 복제. SA: farmily-prod:farmily-app-ai
resource "aws_iam_role" "agentcore" {
  name = "prod-eks-agentcore-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
        "${local.oidc_host}:sub" = "system:serviceaccount:farmily-prod:farmily-app-ai"
      } }
    }]
  })
}
resource "aws_iam_role_policy" "agentcore" {
  name = "prod-eks-agentcore-policy"
  role = aws_iam_role.agentcore.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "BedrockAccess", Effect = "Allow",
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:ApplyGuardrail"], Resource = "*" },
      { Sid = "MarketplaceAccess", Effect = "Allow",
      Action = ["aws-marketplace:ViewSubscriptions", "aws-marketplace:Subscribe", "aws-marketplace:Unsubscribe"], Resource = "*" },
      { Sid = "LambdaInvoke", Effect = "Allow", Action = "lambda:InvokeFunction", Resource = [
        "arn:aws:lambda:ap-northeast-2:851957594139:function:farmily-select-photo",
      "arn:aws:lambda:ap-northeast-2:851957594139:function:farmily-card-renderer"] },
      { Sid = "S3Access", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"], Resource = [
        "arn:aws:s3:::farmily-s3-bucket", "arn:aws:s3:::farmily-s3-bucket/*",
      "arn:aws:s3:::farmily-templates", "arn:aws:s3:::farmily-templates/*"] },
      { Sid = "SecretsManager", Effect = "Allow", Action = "secretsmanager:GetSecretValue",
      Resource = "arn:aws:secretsmanager:ap-northeast-2:851957594139:secret:farmily/*" },
      { Sid = "CloudWatchMetrics", Effect = "Allow", Action = "cloudwatch:PutMetricData", Resource = "*" },
      # OTel/ADOT export — CloudWatch GenAI Observability (X-Ray Transaction Search + 구조화 로그).
      # ECS farmily-agentcore-task-role 에는 있으나 IRSA 복제 시 누락됐던 권한. 없으면 trace/log export 가 AccessDenied 로 조용히 실패.
      { Sid = "XRayTrace", Effect = "Allow", 
        Action = [
        "xray:PutTraceSegments", 
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
        "xray:GetSamplingStatisticSummaries"
      ], Resource = "*" },
      { Sid = "CloudWatchLogs", Effect = "Allow",
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
      "logs:DescribeLogGroups", "logs:DescribeLogStreams"], Resource = "*" },
    ]
  })
}
output "agentcore_role_arn" { value = aws_iam_role.agentcore.arn }