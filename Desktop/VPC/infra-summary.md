# Farmily ECS 마이그레이션 인프라 구성 정리

## 1. 아키텍처 요약

| 구분 | Dev | Prod |
|------|-----|------|
| AZ | 2개 (ap-northeast-2a, 2c) | 2개 (ap-northeast-2a, 2c) |
| Public Subnet | 2개 (ALB, NAT Gateway) | 2개 (ALB, NAT Gateway x2) |
| Private Subnet | 2개 (ECS, RDS, Redis) | 2개 (ECS, RDS, Redis) |
| NAT Gateway | 1개 | 2개 (AZ별 1개, 고가용성) |
| VPN Client | 비활성화 (필요 시 활성화) | 없음 |
| ECS Task | 1개 | 4개 (AZ별 2개) |
| RDS (PostgreSQL) | 단일 인스턴스 | Multi-AZ (Primary + Standby) |
| Redis (ElastiCache) | 단일 노드 | Primary + Replica |
| S3 | 없음 | 있음 |
| CloudFront | 없음 | 있음 (S3 앞단) |
| CloudWatch | 있음 | 있음 |

---

## 2. 서비스별 배포 위치

| 서비스 | 배포 위치 | 포트 |
|--------|-----------|------|
| 백엔드 API (Spring Boot) | ECS Fargate | 8080 |
| 프론트엔드 웹 (디지털 명함, Vite) | S3 + CloudFront | - |
| 모바일 앱 (Expo) | EAS Build (APK/IPA) | - |

---

## 3. Security Group 구성

| SG | 인바운드 허용 | 포트 |
|----|-------------|------|
| ALB | 외부 전체 (0.0.0.0/0) | 80, 443 |
| ECS | ALB SG에서만 | 8080 |
| RDS | ECS SG에서만 | 5432 (PostgreSQL) |
| Redis | ECS SG에서만 | 6379 |

트래픽 흐름: `외부 → ALB → ECS(백엔드) → RDS / Redis`

---

## 4. Terraform 디렉터리 구조

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars          ← .gitignore (민감정보)
│   │   └── terraform.tfvars.example
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars          ← .gitignore (민감정보)
│       └── terraform.tfvars.example
└── modules/
    ├── vpc/          (VPC, Subnet, IGW, NAT, VPN)
    ├── sg/           (Security Groups)
    ├── ecs/          (ECS Cluster, Service, ALB, IAM)
    ├── rds/          (PostgreSQL RDS)
    ├── elasticache/  (Redis)
    ├── s3/           (S3 Bucket)
    ├── cloudfront/   (CloudFront Distribution)
    └── cloudwatch/   (알람, SNS)
```

---

## 5. 주요 설정값

### 네트워크 (VPC)

| 항목 | Dev | Prod |
|------|-----|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| Public Subnet A | 10.0.1.0/24 | 10.1.1.0/24 |
| Public Subnet C | 10.0.2.0/24 | 10.1.2.0/24 |
| Private Subnet A | 10.0.10.0/24 | 10.1.10.0/24 |
| Private Subnet C | 10.0.11.0/24 | 10.1.11.0/24 |

### ECS

| 항목 | Dev | Prod |
|------|-----|------|
| Task CPU | 256 | 512 |
| Task Memory | 512 MB | 1024 MB |
| Desired Count | 1 | 4 |
| Container Port | 8080 | 8080 |
| Health Check Path | /api/v1/health | /api/v1/health |
| Spring Profile | dev | prod |

### RDS (PostgreSQL)

| 항목 | Dev | Prod |
|------|-----|------|
| Engine | PostgreSQL 15.4 | PostgreSQL 15.4 |
| Instance Class | db.t3.micro | db.t3.small |
| Storage | 20 GB | 50 GB |
| Multi-AZ | 아니오 | 예 |
| DB Name | farmily | farmily |
| Master Username | admin | admin |
| Master Password | urbanworkteam | urbanworkteam |

### ElastiCache (Redis)

| 항목 | Dev | Prod |
|------|-----|------|
| Engine | Redis 7.0 | Redis 7.0 |
| Node Type | cache.t3.micro | cache.t3.small |
| 노드 수 | 1 | 2 (Primary + Replica) |
| Auto Failover | 비활성화 | 활성화 |

### S3 (Prod만)

| 항목 | 값 |
|------|-----|
| Bucket Name | farmily-s3-bucket |
| Versioning | 활성화 |
| Public Access | 전체 차단 |
| 접근 방식 | CloudFront OAC로만 |

### CloudFront (Prod만)

| 항목 | 값 |
|------|-----|
| Origin | S3 (farmily-s3-bucket) |
| Protocol | HTTPS 리다이렉트 |
| 인증서 | CloudFront 기본 인증서 |

### CloudWatch

| 알람 | 임계값 |
|------|--------|
| ECS CPU | 80% 초과 시 |
| ECS Memory | 80% 초과 시 |
| RDS CPU | 80% 초과 시 |

---

## 6. ECS 컨테이너 환경변수

| 환경변수 | 값 (자동 연결) |
|----------|---------------|
| SPRING_PROFILES_ACTIVE | dev / prod |
| DB_URL | jdbc:postgresql://[RDS주소]:5432/farmily |
| DB_USERNAME | admin |
| DB_PASSWORD | urbanworkteam |
| REDIS_HOST | [ElastiCache 주소] |

추가 환경변수 (extra_environment으로 주입 가능):
- JWT_SECRET
- KAKAO_* (OAuth)
- PORTONE_* (결제)
- 기타 외부 서비스 키

---

## 7. AWS 계정 정보

| 항목 | 값 |
|------|-----|
| Account ID | 851957594139 |
| IAM User | kimminseok |
| Region | ap-northeast-2 (서울) |
| ECR Repository | farmily-api |
| ECR URI | 851957594139.dkr.ecr.ap-northeast-2.amazonaws.com/farmily-api |

---

## 8. .gitignore 설정 (GitHub에 올라가지 않는 파일)

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
.terraform.lock.hcl
*.tfvars
!*.tfvars.example
.DS_Store
```

---

## 9. Terraform 실행 방법

```bash
# Dev 환경
cd environments/dev
terraform init
terraform plan
terraform apply

# Prod 환경
cd environments/prod
terraform init
terraform plan
terraform apply
```

---

## 10. 마이그레이션 시 추가 작업

| 순서 | 작업 | 설명 |
|------|------|------|
| 1 | Docker 이미지 빌드 & ECR Push | 백엔드 앱 컨테이너화 → ECR 업로드 |
| 2 | DB 데이터 마이그레이션 | 기존 DB → RDS PostgreSQL 데이터 이관 |
| 3 | Redis 캐시 전략 확인 | 기존 캐시 설정 ECS 환경에 맞게 적용 |
| 4 | 추가 환경변수 등록 | JWT_SECRET, KAKAO, PORTONE 등 extra_environment에 추가 |
| 5 | 디지털 명함 빌드 & S3 업로드 | Vite 빌드 → S3 sync → CloudFront Invalidation |
| 6 | CI/CD 파이프라인 구성 | GitHub Actions 워크플로우 작성 |
| 7 | 도메인 & HTTPS | Route53 + ACM 인증서 연결 (필요 시) |
| 8 | VPN 설정 (Dev) | Private Subnet 직접 접근 필요 시 인증서 생성 후 활성화 |

---

## 11. CI/CD 파이프라인 구조

### Backend Pipeline
```
Code Push → GitHub Actions → Deps Download → Build & Test (Gradle) → SonarCloud Scan
→ Image Build → ECR Push → Deploy
  → dev branch → ECS Fargate (Dev)
  → main branch → Manual Approval → ECS Fargate (Prod)
```

### Frontend-web Pipeline (디지털 명함)
```
Code Push → GitHub Actions → Deps Download → npm ci & Build (Vite)
→ S3 Upload → CloudFront Cache Invalidation → Deploy Complete
```

### Mobile Pipeline (Expo)
```
Code Push → GitHub Actions → Deps Download → TypeScript Check
→ EAS Build (APK/IPA) → Slack Notification
```
