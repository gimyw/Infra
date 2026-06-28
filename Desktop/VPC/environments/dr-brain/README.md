# dr-brain — DR 두뇌 (도쿄 ap-northeast-1)

| Phase | 무엇 | 파일 | 가이드 |
|---|---|---|---|
| 1 | diagnose + advisor — 복제 상태 읽어 한국어 판단(읽기 전용) | `lambdas.tf` · `lambdas/{diagnose,advisor}` | `eks-dr/guide/dr-1-advisor-ai.md` |
| 2 | detect_canary — 도쿄가 서울을 1분마다 probe → 좌표 기록 + SNS 알림(탐지·기록만, 전환 없음) | `coordinator.tf` · `canary.tf` · `eventbridge.tf` · `lambdas/detect_canary` | `eks-dr/guide/dr-2-detect-coordinator.md` |
| 3 | Step Functions + Slack 승인 — 진단→AI분석→사람 승인 대기를 하나로 잇기(**promote 없는 dry-run**) | `slack.tf` · `function_url.tf` · `stepfunctions.tf` · `lambdas/{slack_notify,slack_callback}` | `eks-dr/guide/dr-3-stepfunctions-slack.md` |

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

---

## Phase 3 (Step Functions + Slack 승인 — promote 없는 dry-run)

지금까지의 조각(`diagnose`·`advisor`)을 **Step Functions** 하나로 꿰고, 그 중간에 **사람 승인 게이트**를 넣는다.
워크플로우가 Slack 카드를 띄우고 `waitForTaskToken`으로 **멈춰 기다리다가**, 누군가 [승인]을 누르면 그 지점부터 재개한다.
단 이번 단계는 **promote를 걸지 않는 dry-run** — [승인]을 눌러도 `WouldFence`(Succeed)로만 끝난다. 흐름·승인 배관을 먼저 단단히.
가이드: `eks-infra/eks-dr/guide/dr-3-stepfunctions-slack.md`

### 추가된 자산
- `lambdas/slack_notify/handler.py` — taskToken+한국어 판단을 받아 [승인]/[거부] 카드 게시. 토큰은 짧은 id로 `dr-brain-tasktokens`에 보관
- `lambdas/slack_callback/handler.py` — 버튼 클릭 수신, **서명검증**(HMAC·5분 재전송 방지) → `SendTaskSuccess`로 흐름 재개
- `slack.tf` — `dr-brain-tasktokens` 테이블 + slack 두 Lambda + IAM(dr-1의 `lambda_assume` 재사용, 둘 다 VPC 밖)
- `function_url.tf` — `slack_callback`에 공개 Function URL(AuthType NONE) + 호출 권한 + `output slack_callback_url`
- `stepfunctions.tf` — `dr-brain-failover` 상태기계: `Diagnose → AIAnalyze → PostApproval(waitForTaskToken) → Decide → WouldFence/Rejected`

### ★ 적용 전 — Slack 앱 만들기 (콘솔 예외, ~15분)
Slack 앱은 AWS 리소스가 아니라 Terraform 대상이 아니다(Bedrock 모델 액세스와 함께 콘솔로 하는 단 둘 중 하나).
**워크스페이스 앱 설치 권한**이 필요하다 — 없으면 권한 가진 팀원에게 요청한다.

1. <https://api.slack.com/apps> ▸ Create New App ▸ From scratch (이름 `DR Failover Bot`)
2. OAuth & Permissions ▸ Bot Token Scopes에 `chat:write` ▸ Install to Workspace ▸ **Bot User OAuth Token**(`xoxb-…`) 복사
3. Basic Information ▸ **Signing Secret** 복사
4. 알림 채널(예: `#dr-alerts`)에 봇 초대 (`/invite @DR Failover Bot`)
5. (apply 후) Interactivity & Shortcuts ▸ 켜고 Request URL에 **`slack_callback_url`** 붙여넣기
6. 세 값을 시크릿에 저장(IAM은 `farmily/dr/slack-*` 와일드카드라 이 시크릿이 없어도 apply는 통과):

```bash
aws secretsmanager create-secret --region ap-northeast-1 --name farmily/dr/slack \
  --secret-string '{"bot_token":"xoxb-...","signing_secret":"...","channel":"#dr-alerts"}'
```

> ⚠️ Signing Secret을 코드에 박지 말 것 — 노출되면 누구나 가짜 "승인"을 보낼 수 있다(Phase 4부터 치명적).

### 적용

```bash
cd environments/dr-brain
terraform plan     # ★ 검수: "X to add, 0 to change, 0 to destroy" (Phase 1·2·dr/prod 무변경)
terraform apply
terraform output slack_callback_url   # ← 이 URL을 위 5번(Slack Interactivity)에 채운다
```

### 검증 (apply + Slack 시크릿 등록 후)

```bash
# dry-run 실행 시작(빈 입력) → Slack에 [승인]/[거부] 카드가 떠야 함
aws stepfunctions start-execution --region ap-northeast-1 \
  --state-machine-arn $(aws stepfunctions list-state-machines --region ap-northeast-1 \
    --query "stateMachines[?name=='dr-brain-failover'].stateMachineArn" --output text) \
  --input '{}'
```
- [승인] → 멈춘 실행이 `WouldFence`로 재개·성공. [거부] → `Rejected`. 15분 무응답 → `TimeoutSeconds`로 종료.
- 가짜 서명으로 Function URL을 호출하면 401.
- 클릭 후 `dr-brain-tasktokens`에서 해당 항목이 삭제되는지 확인.

> 참고: 이번 Phase 3는 **실행을 사람이 수동 start** 한다(dry-run을 반복해 토큰 왕복·서명·타임아웃을 다지는 게 목적).
> 탐지(canary/SNS) → Step Functions 자동 발동 배선은 Phase 4에서 promote와 함께 붙인다.

## 검증 완료 (Claude) — Phase 3
- `terraform fmt` 무변경(스타일 일치), `terraform validate` → **Success**
- 가이드 `dr-3` 코드 그대로 이식. 단 `slack_callback`에 **Function URL base64 본문 처리 1줄**(`isBase64Encoded`) 추가 — 서명검증·parse 이전에 raw로 되돌림
- `lambda_assume`(iam.tf)·`data.aws_caller_identity.me`(data.tf) 재사용. slack 두 Lambda는 VPC 밖 → SG drift 무관
- 변수 추가 없음(slack 시크릿명·채널은 시크릿 JSON 내부) → `variables.tf`·`terraform.tfvars` 무변경
