# Farmily ECS 마이그레이션 인프라 구성 정리

## 1. 아키텍처 요약

| 구분 | Dev | Prod |
| --- | --- | --- |
| AZ | 2개 (ap-northeast-2a, 2c) | 2개 (ap-northeast-2a, 2c) |
| Public Subnet | 2개 (ALB, NAT Gateway) | 2개 (ALB, NAT Gateway x2) |
| Private Subnet | 2개 (ECS, RDS, Redis) | 2개 (ECS, RDS, Redis) |
| NAT Gateway | 1개 | 2개 (AZ별 1개, 고가용성) |
| VPN Client | 비활성화 (필요 시 활성화) | 없음 |
| ECS Task | 1개 | 4개 (AZ별 2개) |
| RDS (PostgreSQL) | 단일 인스턴스 | Multi-AZ (Primary + Standby) |
| Redis (ElastiCache) | 단일 노드 | Primary + Replica |
| S3 | 있음 (VPC Endpoint로 접근) | 있음 (CloudFront OAC 경유) |
| CloudFront | 없음 | 있음 (S3 앞단, HTTPS) |
| CloudWatch | 있음 | 있음 |
| S3 VPC Endpoint | 있음 (Gateway) | 있음 (Gateway) |
| Bedrock AI | 없음 | 토글 방식 (ai_provider 변수로 활성화) |

---

## 2. 서비스별 배포 위치

| 서비스 | 배포 위치 | 포트 |
| --- | --- | --- |
| 백엔드 API (Spring Boot) | ECS Fargate | 8080 |
| 프론트엔드 웹 (디지털 명함, Vite) | S3 + CloudFront | 443 (HTTPS) |
| 모바일 앱 (Expo) | EAS Build (APK/IPA) | - |

---

## 3. Security Group 구성

| SG | 인바운드 허용 | 포트 |
| --- | --- | --- |
| ALB | 외부 전체 (0.0.0.0/0) | 80, 443 |
| ECS | ALB SG에서만 | 8080 |
| RDS | ECS SG에서만 | 5432 (PostgreSQL) |
| Redis | ECS SG에서만 | 6379 |

트래픽 흐름: `외부 → ALB(80/443) → ECS(백엔드 8080) → RDS / Redis`

S3 접근: `ECS(Private Subnet) → VPC Gateway Endpoint → S3`

---

## 4. HTTPS (443) 구성

- ALB에 HTTPS 리스너(443) 구현 완료
- ACM 인증서 발급 후 `alb_certificate_arn` 값 입력하면 자동 활성화
- 활성화 시: HTTP(80) → HTTPS(443) 리다이렉트
- 미발급 상태: HTTP(80)로 동작
- TLS 정책: `ELBSecurityPolicy-TLS13-1-2-2021-06`

---

## 5. Terraform 디렉터리 구조

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
    ├── vpc/          (VPC, Subnet, IGW, NAT, VPN, S3 VPC Endpoint)
    ├── sg/           (Security Groups)
    ├── ecs/          (ECS Cluster, Service, ALB, IAM, S3 Policy, Bedrock Policy, HTTPS)
    ├── rds/          (PostgreSQL RDS)
    ├── elasticache/  (Redis)
    ├── s3/           (S3 Bucket)
    ├── cloudfront/   (CloudFront Distribution + OAC)
    └── cloudwatch/   (알람, SNS)
```

---

## 6. 주요 설정값

### 네트워크 (VPC)

| 항목 | Dev | Prod |
| --- | --- | --- |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| Public Subnet A | 10.0.1.0/24 | 10.1.1.0/24 |
| Public Subnet C | 10.0.2.0/24 | 10.1.2.0/24 |
| Private Subnet A | 10.0.10.0/24 | 10.1.10.0/24 |
| Private Subnet C | 10.0.11.0/24 | 10.1.11.0/24 |
| S3 VPC Endpoint | Gateway (Private RT 연결) | Gateway (Private RT 연결) |

### ECS

| 항목 | Dev | Prod |
| --- | --- | --- |
| Task CPU | 256 | 512 |
| Task Memory | 512 MB | 1024 MB |
| Desired Count | 1 | 4 |
| Container Port | 8080 | 8080 |
| Health Check Path | /api/v1/health | /api/v1/health |
| Spring Profile | dev | prod |
| ALB HTTPS | ACM 발급 후 활성화 | ACM 발급 후 활성화 |
| Task Definition 관리 | lifecycle ignore_changes (CI/CD 소유권 분리) | 동일 |
| Task Role S3 권한 | Get/Put/Delete/List + ACL | 동일 |
| Task Role Bedrock 권한 | 없음 | ai_provider=bedrock 시 활성화 |

### RDS (PostgreSQL)

| 항목 | Dev | Prod |
| --- | --- | --- |
| Engine | PostgreSQL 16.4 | PostgreSQL 16.4 |
| Instance Class | db.t3.micro | db.t3.small |
| Storage | 20 GB | 50 GB |
| Multi-AZ | 아니오 | 예 |
| Backup Retention | 1일 | 7일 |
| DB Name | farmily | farmily |

### ElastiCache (Redis)

| 항목 | Dev | Prod |
| --- | --- | --- |
| Engine | Redis 7.0 | Redis 7.0 |
| Node Type | cache.t3.micro | cache.t3.small |
| 노드 수 | 1 | 2 (Primary + Replica) |
| Auto Failover | 비활성화 | 활성화 |

### S3

| 항목 | Dev | Prod |
| --- | --- | --- |
| Bucket Name | farmily-dev-s3-bucket | farmily-s3-bucket |
| Versioning | 활성화 | 활성화 |
| Public Access | 전체 차단 | 전체 차단 |
| 접근 방식 | VPC Endpoint (내부) | CloudFront OAC (외부) |

### CloudFront (Prod만)

| 항목 | 값 |
| --- | --- |
| Origin | S3 (farmily-s3-bucket) |
| OAC | 활성화 (sigv4 서명) |
| Protocol | HTTPS (443) 리다이렉트 |
| 인증서 | CloudFront 기본 인증서 |
| S3 Bucket Policy | CloudFront SourceArn 조건부 허용 (root에서 관리) |

### CloudWatch

| 알람 | 임계값 |
| --- | --- |
| ECS CPU | 80% 초과 시 |
| ECS Memory | 80% 초과 시 |
| RDS CPU | 80% 초과 시 |

---

## 7. ECS 컨테이너 환경변수

### 기본 (테라폼 자동 주입)

| 환경변수 | 값 |
| --- | --- |
| SPRING_PROFILES_ACTIVE | dev / prod |
| DB_URL | jdbc:postgresql://[RDS주소]:5432/farmily |
| DB_USERNAME | (tfvars에서 주입) |
| DB_PASSWORD | (tfvars에서 주입) |
| REDIS_HOST | [ElastiCache 주소] |

### locals로 자동 주입 (S3/AI 관련)

| 환경변수 | Dev | Prod |
| --- | --- | --- |
| S3_BUCKET | farmily-dev-s3-bucket | farmily-s3-bucket |
| S3_REGION | ap-northeast-2 | ap-northeast-2 |
| CDN_BASE_URL | - | https://[CloudFront 도메인] |
| AI_PROVIDER | - | mock (default) / bedrock |
| AWS_REGION | - | us-west-2 (Bedrock용) |
| BEDROCK_AGENT_ID | - | (콘솔에서 생성 후 tfvars 주입) |
| BEDROCK_AGENT_ALIAS_ID | - | (콘솔에서 생성 후 tfvars 주입) |

### extra_environment로 추가 주입 가능

- JWT_SECRET
- KAKAO_* (OAuth)
- PORTONE_* (결제)
- 기타 외부 서비스 키

---

## 8. IAM 역할 구성

| Role | 용도 | 정책 |
| --- | --- | --- |
| ${env}-ecs-execution-role | Task 실행 (이미지 Pull, 로그 전송) | AmazonECSTaskExecutionRolePolicy |
| ${env}-ecs-task-role | 앱 런타임 권한 | S3 Get/Put/Delete/List + ACL, Bedrock(조건부) |

---

## 9. AWS 계정 정보

| 항목 | 값 |
| --- | --- |
| Account ID | 851957594139 |
| IAM User | kimminseok |
| Region | ap-northeast-2 (서울) |
| ECR Repository | farmily-api |
| ECR URI | 851957594139.dkr.ecr.ap-northeast-2.amazonaws.com/farmily-api |

---

## 10. .gitignore 설정 (GitHub에 올라가지 않는 파일)

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

## 11. Terraform 실행 방법

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

## 12. 마이그레이션 시 추가 작업

| 순서 | 작업 | 설명 |
| --- | --- | --- |
| 1 | Docker 이미지 빌드 & ECR Push | 백엔드 앱 컨테이너화 → ECR 업로드 |
| 2 | DB 데이터 마이그레이션 | 기존 DB → RDS PostgreSQL 데이터 이관 |
| 3 | Redis 캐시 전략 확인 | 기존 캐시 설정 ECS 환경에 맞게 적용 |
| 4 | 추가 환경변수 등록 | JWT_SECRET, KAKAO, PORTONE 등 extra_environment에 추가 |
| 5 | ACM 인증서 발급 | 도메인 인증서 발급 → alb_certificate_arn에 등록 → HTTPS 활성화 |
| 6 | 디지털 명함 빌드 & S3 업로드 | Vite 빌드 → S3 sync → CloudFront Invalidation (Prod) |
| 7 | CI/CD 파이프라인 구성 | GitHub Actions 워크플로우 작성 |
| 8 | 도메인 연결 | Route53 연결 (필요 시) |
| 9 | VPN 설정 (Dev) | Private Subnet 직접 접근 필요 시 인증서 생성 후 활성화 |
| 10 | Bedrock Agent 생성 | 콘솔에서 Agent 생성 후 ID를 tfvars에 주입 |

---

## 13. CI/CD 파이프라인 구조

### Backend Pipeline

```
Code Push → GitHub Actions → Deps Download → Build & Test (Gradle) → SonarCloud Scan
→ Image Build → ECR Push → Deploy (register-task-definition → update-service)
  → dev branch push → ECS Fargate (Dev) 자동 배포
  → main branch merge → Manual Approval → ECS Fargate (Prod)
```

※ Task Definition은 `lifecycle { ignore_changes = [container_definitions] }`로 소유권 분리
- 인프라(CPU/메모리/IAM): 테라폼 관리
- 이미지 교체: CI/CD 관리

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

---

## 주요 변경점 요약

- RDS 엔진 버전 15.4 → 16.4 (현재 코드 기준)
- ECS Task Role에 S3 정책, Bedrock 정책(토글) 추가
- locals.app_environment으로 S3/CDN/Bedrock 환경변수 자동 주입
- Task Definition lifecycle ignore_changes 적용 (CI/CD 소유권 분리)
- IAM 역할 구성 섹션 신규 추가
- CI/CD 배포 전략 명확화 (dev branch → dev 자동, main merge → prod 수동승인)
- Backup Retention 정보 추가 (dev 1일 / prod 7일)
- CloudFront OAC + Bucket Policy 분리 구조 반영
