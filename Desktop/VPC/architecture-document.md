# Farmily Architecture Document

## 1. 개요

| 항목 | 내용 |
| --- | --- |
| 프로젝트명 | Farmily |
| 작성일 | 2026-06-02 |
| 작성자 | kimminseok |
| 버전 | 1.0 |
| 비즈니스 컨텍스트 | ECS 마이그레이션 기반 인프라 구축 |

## 2. 아키텍처 개요

### 시스템 다이어그램

> ECS마이그레이션아키텍처 수정본 참조 (Dev / Prod 환경 분리)

### 데이터 흐름

```
[Backend API]
사용자 → ALB(80/443) → ECS Fargate(8080) → RDS PostgreSQL / Redis

[프론트엔드 웹 - Prod]
사용자 → CloudFront(443) → S3

[프론트엔드 웹 - Dev]
ECS Task → VPC Endpoint → S3

[CI/CD]
Developer → GitHub Push → GitHub Actions → ECR Push → ECS Deploy
Developer → GitHub Push → GitHub Actions → S3 Upload → CloudFront Invalidation
```

### 컴포넌트 목록

| 컴포넌트 | AWS 서비스 | 용도 |
| --- | --- | --- |
| 네트워크 | VPC, Subnet, IGW, NAT Gateway | 네트워크 격리 및 인터넷 접근 |
| 로드밸런서 | ALB | 트래픽 분산, HTTPS 종단 |
| 컨테이너 | ECS Fargate | 백엔드 API 실행 |
| 컨테이너 이미지 | ECR | Docker 이미지 저장소 |
| 데이터베이스 | RDS (PostgreSQL 15.4) | 관계형 데이터 저장 |
| 캐시 | ElastiCache (Redis 7.0) | 세션/캐시 저장 |
| 스토리지 | S3 | 정적 파일 저장 |
| CDN | CloudFront | 정적 콘텐츠 배포 (Prod) |
| 모니터링 | CloudWatch | 메트릭 알람, 로그 |
| 보안 접근 | VPN Client | Dev Private Subnet 접근 |

---

## 3. Operational Excellence (운영 우수성)

### IaC (Infrastructure as Code)

| 도구 | 대상 | 저장소 위치 |
| --- | --- | --- |
| Terraform | VPC, ECS, RDS, ElastiCache, S3, CloudFront, CloudWatch, SG | github.com/urbanworkteam/Infra |

### CI/CD 파이프라인

```
[Backend]
Code Push → GitHub Actions → Deps Download → Build & Test (Gradle) → SonarCloud Scan
→ Image Build → ECR Push → Deploy
  → dev branch → ECS Fargate (Dev)
  → main branch → Manual Approval → ECS Fargate (Prod)

[Frontend-web (디지털 명함)]
Code Push → GitHub Actions → npm ci & Build (Vite) → S3 Upload → CloudFront Invalidation

[Mobile (Expo)]
Code Push → GitHub Actions → TypeScript Check → EAS Build (APK/IPA) → Slack Notification
```

### 관측성 (Observability)

| 도구 | 용도 |
| --- | --- |
| CloudWatch Logs | ECS 컨테이너 로그 수집 (/ecs/{env}-app) |
| CloudWatch Alarms | ECS CPU/Memory, RDS CPU 임계값 알람 |
| SNS | 알람 알림 발송 |

---

## 4. Security (보안)

### 네트워크 보안

| 구분 | 배치 | 접근 경로 |
| --- | --- | --- |
| ALB | Public Subnet | 외부 → ALB (80, 443) |
| ECS | Private Subnet | ALB → ECS (8080) |
| RDS | Private Subnet | ECS → RDS (5432) |
| Redis | Private Subnet | ECS → Redis (6379) |
| S3 | VPC 외부 | VPC Gateway Endpoint (Private) |

### IAM 설계

| Role 이름 | 부여 대상 | 권한 |
| --- | --- | --- |
| {env}-ecs-execution-role | ECS Task 실행 | AmazonECSTaskExecutionRolePolicy (ECR Pull, CloudWatch Logs) |
| {env}-ecs-task-role | ECS Task 런타임 | S3 접근 등 앱 실행 시 필요한 권한 |
| farmily-cicd-github-role | GitHub Actions (OIDC) | ECR Push, ECS Deploy |

### 데이터 보호

| 구분 | 대상 | 암호화 방식 |
| --- | --- | --- |
| 전송 중 | ALB ↔ 클라이언트 | TLS 1.3 (ACM 인증서 발급 후) |
| 저장 시 | RDS | AES-256 (AWS 관리형) |
| 저장 시 | S3 | AES-256 (AWS 관리형) |
| 저장 시 | ECR | AES-256 |

---

## 5. Reliability (안정성)

### 고가용성 설계

| 구성 요소 | HA 전략 | AZ 분산 |
| --- | --- | --- |
| ECS (Prod) | Task 4개 분산 | 2 AZ (a, c) |
| RDS (Prod) | Multi-AZ Standby | 자동 페일오버 |
| Redis (Prod) | Primary + Replica | 자동 페일오버 |
| NAT Gateway (Prod) | AZ별 1개 | 2 AZ |
| ALB | 자동 분산 | 2 AZ |

### 백업 정책

| 대상 | 방식 | 보관 기간 |
| --- | --- | --- |
| RDS (Dev) | 자동 백업 | 1일 |
| RDS (Prod) | 자동 백업 | 7일 |

---

## 6. Performance Efficiency (성능 효율성)

### 컴퓨팅

| 서비스 | 스펙 (Dev / Prod) | 선택 이유 |
| --- | --- | --- |
| ECS Fargate | 256 CPU/512MB / 512 CPU/1024MB | 서버리스, 운영 부담 최소화 |

### 데이터베이스

| 서비스 | 엔진/버전 | 구성 | 선택 이유 |
| --- | --- | --- | --- |
| RDS | PostgreSQL 15.4 | Dev: db.t3.micro / Prod: db.t3.small, Multi-AZ | 관리형 DB, 자동 백업/페일오버 |
| ElastiCache | Redis 7.0 | Dev: cache.t3.micro x1 / Prod: cache.t3.small x2 | 관리형 캐시, 자동 페일오버 |

### 네트워크 & CDN

| 서비스 | 용도 |
| --- | --- |
| CloudFront | 정적 파일(디지털 명함) HTTPS 배포 (Prod) |
| S3 VPC Endpoint | Private Subnet에서 S3 직접 접근 (NAT 비용 절감) |

---

## 7. Cost Optimization (비용 최적화)

### 월 예상 비용 (서울 리전, 최소 트래픽 기준)

**Dev 환경**

| 서비스 | 스펙 | 월 예상 비용 (USD) |
| --- | --- | --- |
| NAT Gateway | 1개 × 24h | ~$45 |
| ALB | 1개 | ~$22 |
| ECS Fargate | 256 CPU / 512MB × 1 Task | ~$12 |
| RDS PostgreSQL | db.t3.micro, 20GB, Single-AZ | ~$17 |
| ElastiCache Redis | cache.t3.micro × 1 | ~$13 |
| S3 | 저용량 | ~$1 |
| CloudWatch | 알람 3개 | ~$3 |
| **Dev 합계** | | **~$113** |

**Prod 환경**

| 서비스 | 스펙 | 월 예상 비용 (USD) |
| --- | --- | --- |
| NAT Gateway | 2개 × 24h | ~$90 |
| ALB | 1개 | ~$22 |
| ECS Fargate | 512 CPU / 1024MB × 4 Task | ~$97 |
| RDS PostgreSQL | db.t3.small, 50GB, Multi-AZ | ~$58 |
| ElastiCache Redis | cache.t3.small × 2 | ~$50 |
| S3 | 저용량 | ~$1 |
| CloudFront | 기본 트래픽 | ~$5 |
| CloudWatch | 알람 3개 | ~$3 |
| **Prod 합계** | | **~$326** |

**총 예상 비용: ~$439/월**

> ⚠️ 최소 트래픽 기준 추정치. 실제 비용은 데이터 전송량, 요청 수, 스토리지 사용량에 따라 변동. 정확한 견적은 AWS Pricing Calculator 참조.

### 비용 최적화 전략

| 전략 | 적용 내용 |
| --- | --- |
| Dev/Prod 분리 | Dev는 최소 스펙 (Single-AZ, Task 1개) |
| S3 VPC Endpoint | NAT Gateway 통한 S3 트래픽 비용 절감 |
| Fargate | EC2 대비 유휴 비용 없음, 사용한 만큼만 과금 |

---

## 8. 인프라 설정값 상세

### VPC CIDR

| Subnet | Dev CIDR | Prod CIDR | AZ |
| --- | --- | --- | --- |
| Public A | 10.0.1.0/24 | 10.1.1.0/24 | ap-northeast-2a |
| Public C | 10.0.2.0/24 | 10.1.2.0/24 | ap-northeast-2c |
| Private A | 10.0.10.0/24 | 10.1.10.0/24 | ap-northeast-2a |
| Private C | 10.0.11.0/24 | 10.1.11.0/24 | ap-northeast-2c |

### ECS 환경변수

| 환경변수 | 값 |
| --- | --- |
| SPRING_PROFILES_ACTIVE | dev / prod |
| DB_URL | jdbc:postgresql://[RDS주소]:5432/farmily |
| DB_USERNAME | admin |
| DB_PASSWORD | (sensitive) |
| REDIS_HOST | [ElastiCache endpoint] |
| extra_environment | JWT_SECRET, KAKAO_*, PORTONE_* 등 추후 추가 |

### 외부 서비스 연동 (Prod)

| 서비스 | 용도 |
| --- | --- |
| Kakao | OAuth 2.0 인증 |
| PortOne | 결제 |
| 가상팜 | 날씨 API |
| FCM | 푸시 알림 |
| Amazon Bedrock | AI Agent |
