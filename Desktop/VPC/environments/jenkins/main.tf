# Jenkins CI/CD용 IAM 역할 3개 (계정 레벨 공유 — 독립 state)
#
# 신뢰 체인:
#   EC2(Jenkins) → farmily-jenkins-ec2-role (인스턴스 프로파일)
#                      ├─ jenkins-tf-runner-dev  (ExternalId=farmily-tf-dev)
#                      └─ jenkins-tf-runner-prod (ExternalId=farmily-tf-prod)
#
#    tf-runner에 iam:CreateRole 포함 — 권한상승 봉쇄용 farmily-irsa-boundary 정책은
#    Jenkins 켤 때 일괄 부착 예정 (PROJECT_CONTEXT boundary 갭 항목).

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
  region = "ap-northeast-2"
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  runner_path  = "/farmily/irsa/"     # Jenkinsfile ROLE_ARN 경로와 일치
  state_bucket = "farmily-terraform-state"
  lock_table   = "terraform-locks"

  #    IAM 광범위 — Terraform이 EKS·IRSA·ECS 등 전체 스택을 apply하려면 필수.
  #    서비스별 주석 참고. boundary 미적용 기간 중 사용에 주의.
  tf_runner_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # VPC·서브넷·SG·NAT·IGW·ALB·Karpenter 노드그룹 등 네트워크 전체
        Sid      = "Networking"
        Effect   = "Allow"
        Action   = ["ec2:*", "elasticloadbalancing:*", "autoscaling:*", "application-autoscaling:*"]
        Resource = "*"
      },
      {
        Sid      = "EKS"
        Effect   = "Allow"
        Action   = ["eks:*"]
        Resource = "*"
      },
      {
        # IRSA 역할 생성·삭제·정책 부착 포함 — boundary로 권한상승 경로 차단 예정
        Sid    = "IAM"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:ListRoles",
          "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:GetPolicy", "iam:GetPolicyVersion",
          "iam:ListPolicies", "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:TagPolicy",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:PassRole",
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:TagOpenIDConnectProvider",
        ]
        Resource = "*"
      },
      {
        # Terraform 원격 state 읽기·쓰기 (state 버킷만 스코프)
        Sid    = "StateStorage"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
        Resource = [
          "arn:aws:s3:::${local.state_bucket}",
          "arn:aws:s3:::${local.state_bucket}/*",
        ]
      },
      {
        # Terraform state lock
        Sid    = "StateLock"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
        Resource = "arn:aws:dynamodb:ap-northeast-2:${local.account_id}:table/${local.lock_table}"
      },
      {
        # 앱용 S3 버킷 (farmily-* 전체) — modules/s3 관리
        Sid      = "S3App"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["arn:aws:s3:::farmily-*", "arn:aws:s3:::farmily-*/*"]
      },
      {
        Sid      = "Database"
        Effect   = "Allow"
        Action   = ["rds:*", "elasticache:*"]
        Resource = "*"
      },
      {
        Sid      = "CDN"
        Effect   = "Allow"
        Action   = ["cloudfront:*", "acm:*", "route53:*", "route53domains:*"]
        Resource = "*"
      },
      {
        Sid      = "Security"
        Effect   = "Allow"
        Action   = ["wafv2:*", "shield:*"]
        Resource = "*"
      },
      {
        # ESO ExternalSecret이 참조하는 farmily/* 시크릿만 스코프
        Sid    = "Secrets"
        Effect = "Allow"
        Action = ["secretsmanager:*"]
        Resource = "arn:aws:secretsmanager:ap-northeast-2:${local.account_id}:secret:farmily/*"
      },
      {
        Sid      = "Observability"
        Effect   = "Allow"
        Action   = ["cloudwatch:*", "logs:*"]
        Resource = "*"
      },
      {
        # ECR 레포 관리 + ECS (ECS→EKS 전환 중 잔존)
        Sid      = "Containers"
        Effect   = "Allow"
        Action   = ["ecr:*", "ecs:*"]
        Resource = "*"
      },
      {
        # ecs-scheduler 모듈: Lambda + EventBridge Scheduler
        Sid      = "Compute"
        Effect   = "Allow"
        Action   = ["lambda:*", "scheduler:*", "events:*", "sqs:*", "sns:*"]
        Resource = "*"
      },
      {
        Sid    = "Misc"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath",
          "ssm:PutParameter", "ssm:DeleteParameter",
          "kms:Describe*", "kms:List*", "kms:Get*",
          "kms:CreateKey", "kms:TagResource", "kms:CreateAlias", "kms:DeleteAlias",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
    ]
  })
}

# ────────────────────────────────────────────────────────────────
# 1. EC2 인스턴스 프로파일 (Jenkins EC2에 부착)
# ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "jenkins_ec2" {
  name = "farmily-jenkins-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    project = "farmily"
    team    = "urbanwork"
    purpose = "jenkins-ec2-instance-profile"
  }
}

resource "aws_iam_role_policy" "jenkins_ec2" {
  name = "jenkins-ec2-permissions"
  role = aws_iam_role.jenkins_ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # tf-runner를 assume. ExternalId 검증은 runner trust policy가 담당
        Sid    = "AssumeRunners"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          aws_iam_role.tf_runner_dev.arn,
          aws_iam_role.tf_runner_prod.arn,
        ]
      },
      {
        # farmily-tf-agent 이미지 pull
        # GetAuthorizationToken은 리소스 스코프 불가 — 계정 전체 필수
        Sid    = "EcrPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_ec2" {
  name = "farmily-jenkins-ec2-profile"
  role = aws_iam_role.jenkins_ec2.name
}

resource "aws_iam_role_policy_attachment" "jenkins_ec2_ssm" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ────────────────────────────────────────────────────────────────
# 2. jenkins-tf-runner-dev
# ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "tf_runner_dev" {
  name = "jenkins-tf-runner-dev"
  path = local.runner_path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS =[ "arn:aws:iam::${local.account_id}:role/farmily-jenkins-ec2-role",
                            "arn:aws:iam::${local.account_id}:role/prod-eks-jenkins-tf-role"]}
      Action    = "sts:AssumeRole"
      Condition = {
        # ExternalId 없으면 ec2-role 탈취 시 dev 환경 적용 가능 — confused deputy 방어
        StringEquals = { "sts:ExternalId" = "farmily-tf-dev" }
      }
    }]
  })

  tags = {
    project = "farmily"
    team    = "urbanwork"
    env     = "dev"
    purpose = "jenkins-terraform-runner"
  }
}

resource "aws_iam_role_policy" "tf_runner_dev" {
  name   = "jenkins-tf-runner-dev-policy"
  role   = aws_iam_role.tf_runner_dev.id
  policy = local.tf_runner_policy
}

# ────────────────────────────────────────────────────────────────
# 3. jenkins-tf-runner-prod
# ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "tf_runner_prod" {
  name = "jenkins-tf-runner-prod"
  path = local.runner_path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = [
        "arn:aws:iam::${local.account_id}:role/farmily-jenkins-ec2-role",
        "arn:aws:iam::${local.account_id}:role/prod-eks-jenkins-tf-role",
      ]}
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = "farmily-tf-prod" }
      }
    }]
  })

  tags = {
    project = "farmily"
    team    = "urbanwork"
    env     = "prod"
    purpose = "jenkins-terraform-runner"
  }
}

resource "aws_iam_role_policy" "tf_runner_prod" {
  name   = "jenkins-tf-runner-prod-policy"
  role   = aws_iam_role.tf_runner_prod.id
  policy = local.tf_runner_policy
}
