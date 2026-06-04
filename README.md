# Farmily Infrastructure

Farmily 서비스의 AWS 인프라를 Terraform으로 관리하는 레포지토리입니다.

## 구성 서비스

- **VPC** — Public/Private Subnet, Internet Gateway, NAT Gateway
- **ECS Fargate** — Spring Boot 백엔드 컨테이너 실행 (ALB 연동)
- **RDS** — PostgreSQL 15.4
- **ElastiCache** — Redis 7.0
- **S3** — 정적 파일 저장소
- **CloudFront** — S3 앞단 CDN
- **CloudWatch** — CPU/Memory 알람 + SNS 알림
- **Security Groups** — ALB, ECS, RDS, Redis 간 접근 제어

## 디렉터리 구조

```
.
├── environments/
│   ├── dev/              # 개발 환경
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── prod/             # 프로덕션 환경
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── modules/
    ├── vpc/              # VPC, Subnet, IGW, NAT
    ├── sg/               # Security Groups
    ├── ecs/              # ECS Cluster, Service, ALB, IAM
    ├── rds/              # PostgreSQL RDS
    ├── elasticache/      # Redis
    ├── s3/               # S3 Bucket
    ├── cloudfront/       # CloudFront Distribution
    └── cloudwatch/       # 알람, SNS
```

## 사용법

```bash
cd environments/dev  # 또는 environments/prod

cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars에 실제 값 입력

terraform init
terraform plan
terraform apply
```
