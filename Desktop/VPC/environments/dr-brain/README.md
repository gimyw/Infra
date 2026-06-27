# dr-brain — DR 두뇌 (도쿄 ap-northeast-1)

| Phase | 무엇 | 파일 | 가이드 |
|---|---|---|---|
| 1 | diagnose + advisor — 복제 상태 읽어 한국어 판단(읽기 전용) | `lambdas.tf` · `lambdas/{diagnose,advisor}` | `eks-dr/guide/dr-1-advisor-ai.md` |
| 2 | detect_canary — 도쿄가 서울을 1분마다 probe → 좌표 기록 + SNS 알림(탐지·기록만, 전환 없음) | `coordinator.tf` · `canary.tf` · `eventbridge.tf` · `lambdas/detect_canary` | `eks-dr/guide/dr-2-detect-coordinator.md` |

---

## Phase 1 (diagnose + advisor)

도쿄에서 도는 Lambda 두 개로 서울 DB의 복제 상태를 읽어 한국어 판단을 만든다. **읽기 전용**(서울에 쓰기 없음).
가이드: `eks-infra/eks-dr/guide/dr-1-advisor-ai.md`

## 사전 준비 — 대부분 끝남 (검수만)

| # | 항목 | 상태 |
|---|---|---|
| 1 | `pip install pg8000 -t lambdas/diagnose/` (의존성) | ✅ 완료 (lambdas/diagnose/ 에 담김) |
| 2 | DB 접속 정보 | ✅ **불필요** — 두 시크릿에서 자동으로 읽음(아래) |
| 3 | Bedrock 모델 액세스 | ✅ 확인됨 — `jp.anthropic.claude-sonnet-4-6` 호출 정상 |
| 4 | data 소스 태그 | ✅ 확인됨 — dr-vpc · dr-private-subnet-a/c · dr-rds-sg 모두 실재 |
| 5 | SG 규칙 주의 | ⚠️ 아래 참고 (검수 필요) |

### 2번이 불필요한 이유 (접속 정보는 이미 다 있음)
diagnose 는 시크릿 두 개를 합쳐 접속한다 — 둘 다 이미 존재하므로 **DB 계정 생성·시크릿 수정이 필요 없다**:
- `farmily/dr/app-infra` → `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_NAME`
- `farmily/dr/app` → `DB_PASSWORD`

`farmilyadmin` 은 마스터 계정이라 복제 상태 함수(`pg_last_wal_*` 등)를 호출할 수 있어 별도 모니터 계정도 불필요.

### 5번 — SG 규칙 검수 (★ plan 결과에서 확인)
`network.tf` 가 `dr-rds-sg` 에 5432 인바운드(standalone rule)를 추가한다. `dr-rds-sg` 는 `environments/dr` 의
sg 모듈이 **inline ingress** 로 관리하므로, **`environments/dr` 를 다시 apply 하면 이 규칙이 drift 로 지워질 수 있다.**
- 부트캠프 단발 실습이면 이대로도 동작한다.
- 영구히 하려면 `environments/dr/main.tf` 의 sg 모듈에서 `enable_lambda_sg=true` 로 하거나 규칙을 모듈로 옮긴다.

## 적용

```bash
cd environments/dr-brain
terraform init
terraform plan     # ★ 검수: "X to add, 0 to change, 0 to destroy"
                   #   특히 network.tf 의 SG 규칙이 dr-rds-sg 를 어떻게 건드리는지
terraform apply
```

## 검증 (apply 후)

```bash
# diagnose 호출 → 복제 지연 JSON
aws lambda invoke --function-name dr-brain-diagnose --region ap-northeast-1 out.json && cat out.json
# advisor 에 diagnose 결과 전달 → 한국어 판단
aws lambda invoke --function-name dr-brain-advisor --region ap-northeast-1 \
  --payload "{\"diagnose\": $(cat out.json)}" --cli-binary-format raw-in-base64-out adv.json && cat adv.json
```

## 검증 완료 (Claude)
- `terraform fmt` 통과, `terraform validate` → **Success** (실제 dr-brain 디렉터리)
- validate 가 잡은 버그 1건 수정(SG rule description 의 `>` 금지문자)
- Bedrock·태그·시크릿 키 전부 라이브 확인

---

## Phase 2 (detect_canary — 탐지·기록만, 전환 없음)

도쿄 canary가 1분마다 **서울 prod ALB `/health` 를 인터넷으로 probe**(+ 선택적 Route53 지표 교차검증)해서,
죽었다고 확신되면 좌표(DynamoDB)에 기록하고 SNS로 알린다. promote·트래픽 전환은 없다.
가이드: `eks-infra/eks-dr/guide/dr-2-detect-coordinator.md`

### 추가된 자산
- `coordinator.tf` — DynamoDB `dr-brain-coordinator`(좌표) + SNS `dr-brain-approvals`(알림)
- `lambdas/detect_canary/handler.py` — 표준 라이브러리만(의존성 zip 불필요, **VPC 불필요**)
- `canary.tf` — `dr-brain-canary` Lambda + IAM(dr-1의 `lambda_assume` 재사용)
- `eventbridge.tf` — EventBridge Scheduler `rate(1 minute)`

### 적용 전 검수 (★ 사람이 채울 한 곳)
`terraform.tfvars` 의 **`seoul_health_url`** 을 서울 prod ALB **직접 DNS** 로 교체한다.
⚠️ **failover 도메인(`api.farmily.info`) 금지** — 서울이 죽으면 도쿄로 넘어가 canary가 "서울 정상"으로 오판·플랩한다.

```bash
# 서울 prod ALB 직접 DNS 확인
aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query "LoadBalancers[?contains(LoadBalancerName,'prod')].DNSName" --output text
```

### 적용

```bash
cd environments/dr-brain
terraform plan     # ★ 검수: "X to add, 0 to change, 0 to destroy"
terraform apply

# apply 후 1회: 좌표 초기 상태 seed
aws dynamodb put-item --region ap-northeast-1 --table-name dr-brain-coordinator \
  --item '{"key":{"S":"primary"},"current_primary":{"S":"seoul"},"epoch":{"N":"0"},"fencing_in_progress":{"BOOL":false}}'
```

### 검증 (apply 후)

```bash
# canary 수동 호출 → 판정 JSON (서울 정상이면 confirmed_down:false 가 정상)
aws lambda invoke --function-name dr-brain-canary --region ap-northeast-1 c.json && cat c.json

# 1~2분 뒤 좌표가 1분마다 갱신되는지 (seoul_health, last_probe)
aws dynamodb get-item --region ap-northeast-1 --table-name dr-brain-coordinator \
  --key '{"key":{"S":"primary"}}'
```

## 검증 완료 (Claude) — Phase 2
- `terraform fmt` 무변경(스타일 일치), `terraform validate` → **Success**
- 가이드 `dr-2` 코드 그대로 이식. 단 placeholder 였던 `SEOUL_HEALTH_URL` 은 `var.seoul_health_url` 로 빼 `tfvars` 한 곳에서 채우게 함(+ `route53_hc_id` 선택 변수)
- `lambda_assume`(iam.tf) 재사용 — canary 는 VPC 밖, SG/네트워크 변경 없음 → Phase 1 의 `dr-rds-sg` drift 위험과 무관
