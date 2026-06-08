# Terraform 환경변수 설정값

> ⚠️ 이 파일은 실제 값이 포함되어 있으므로 GitHub에 올리지 마세요.
> `.gitignore`에 `*.tfvars`가 등록되어 있어 자동 제외됩니다.

---

## Dev 환경 (environments/dev/terraform.tfvars)

```hcl
region          = "ap-northeast-2"
container_image = "851957594139.dkr.ecr.ap-northeast-2.amazonaws.com/farmily-api:latest"
db_name         = "farmily"
db_username     = "admin"
db_password     = "urbanworkteam"
```

---

## Prod 환경 (environments/prod/terraform.tfvars)

```hcl
region          = "ap-northeast-2"
container_image = "851957594139.dkr.ecr.ap-northeast-2.amazonaws.com/farmily-api:latest"
db_name         = "farmily"
db_username     = "admin"
db_password     = "urbanworkteam"
s3_bucket_name  = "farmily-s3-bucket"
```

---

## 미등록 (추후 등록 필요)

| 변수 | 설명 | 시점 |
|------|------|------|
| `alb_certificate_arn` | ACM 인증서 ARN (HTTPS 활성화) | 도메인 인증서 발급 후 |
| `vpn_server_cert_arn` | VPN 서버 인증서 ARN | VPN 사용 시 |
| `vpn_client_cert_arn` | VPN 클라이언트 인증서 ARN | VPN 사용 시 |
| `extra_environment` | JWT_SECRET, KAKAO_*, PORTONE_* 등 | 앱 환경변수 확정 후 |

---

## 자동 연결되는 값 (직접 입력 불필요)

| 환경변수 | 소스 | 설명 |
|----------|------|------|
| DB_URL | module.rds.address | RDS 생성 후 자동 주입 |
| REDIS_HOST | module.elasticache.primary_endpoint | Redis 생성 후 자동 주입 |
| SPRING_PROFILES_ACTIVE | spring_profile 변수 | dev / prod |
| Security Group IDs | module.sg 출력값 | SG 모듈에서 자동 생성 및 연결 |

---

## 사용 방법

1. 위 내용을 각 환경 디렉터리에 `terraform.tfvars` 파일로 생성
2. `terraform init` → `terraform plan` → `terraform apply`
