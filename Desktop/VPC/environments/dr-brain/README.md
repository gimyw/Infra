# dr-brain — DR 두뇌 (도쿄 ap-northeast-1)

| Phase | 무엇 | 파일 | 가이드 |
|---|---|---|---|
| 1 | diagnose + advisor — 복제 상태 읽어 한국어 판단(읽기 전용) | `lambdas.tf` · `lambdas/{diagnose,advisor}` | `eks-dr/guide/dr-1-advisor-ai.md` |
| 2 | detect_canary — 도쿄가 서울을 1분마다 probe → 좌표 기록 + SNS 알림(탐지·기록만, 전환 없음) | `coordinator.tf` · `canary.tf` · `eventbridge.tf` · `lambdas/detect_canary` | `eks-dr/guide/dr-2-detect-coordinator.md` |
| 3 | Step Functions + Slack 승인 — 진단→AI분석→사람 승인 대기를 하나로 잇기(**promote 없는 dry-run**) | `slack.tf` · `function_url.tf` · `stepfunctions.tf` · `lambdas/{slack_notify,slack_callback}` | `eks-dr/guide/dr-3-stepfunctions-slack.md` |
| 4 | fence·promote·flip·verify — 승인 뒤 **진짜 비가역 동작**(arm_promote 게이트) + FIS 게임데이 | `fence.tf` · `promote.tf` · `flip.tf` · `verify.tf` · `stepfunctions.tf` · `lambdas/{fence,promote,flip_coordinator,verify}` | `eks-dr/guide/dr-4-fence-promote-fis.md` |
| 7 | **검수 에이전트** — promote 직후 split-brain을 읽기전용 도구로 **스스로 조사**하는 AI 에이전트(DIY Converse tool-use) | `audit_agent.tf` · `verify.tf`(확장) · `stepfunctions.tf` · `lambdas/audit_agent` | `eks-dr/guide/dr-7-failover-audit.md` |
| 5 | 회고 — 실행 히스토리 → 실측 RTO/RPO 한국어 보고서 → S3(어느 경로든 마지막에 남김) | `retrospective.tf` · `stepfunctions.tf` · `lambdas/retrospective` | `eks-dr/guide/dr-5-retrospective.md` |

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

---

## Phase 4 (fence · promote · flip · verify — 진짜 비가역 동작 + FIS)

Phase 3의 `WouldFence`(빈 자리)를 실제 체인으로 채운다 — 구 서울 차단(**fence**) → 도쿄 승격(**promote**) →
좌표 전환(**flip**) → 검증(**verify**). 되돌릴 수 없는 단계라, 모든 위험 동작을 입력 플래그 **`arm_promote`** 뒤에 둔다.
가이드: `eks-infra/eks-dr/guide/dr-4-fence-promote-fis.md`

### 추가된 자산
- `lambdas/fence/handler.py` — epoch CAS 잠금 → 서울 닿으면 `prod-rds` SG를 빈 `dr-brain-fence-sg`로 원자 교체. 못 닿으면 `fence_pending`(서울 복귀 시 재시도).
- `lambdas/promote/handler.py` — `dr-rds` promote_read_replica **시작만**(완료대기는 SFN 폴링).
- `lambdas/flip_coordinator/handler.py` — 좌표 `current_primary=tokyo`(epoch 소유 확인) + `farmily/dr/promoted-db` 시크릿에 새 엔드포인트.
- `lambdas/verify/handler.py` — 새 primary 쓰기 스모크 + `pg_is_in_recovery()` + 앱 200. **pg8000 의존**(diagnose처럼 벤더링).
- `fence.tf`(서울 prod VPC 참조 + 빈 fence-sg) · `promote.tf` · `flip.tf` · `verify.tf`(VPC 안) + `stepfunctions.tf` 교체.

### ★ 게임데이 안전핀 — `arm_promote`
- 상태기계 입력의 기본은 **`{"arm_promote": false}`**. 이 값이 false면 fence·promote가 **실제로는 아무것도 안 하고 로그만** 남기고 `DryRunDone`으로 끝난다.
- 진짜로 승격하려는, 신중히 결정한 단 한 번만 `true`로 넣는다. **진짜 `dr-rds`는 게임데이에서 promote 금지** — 풀 드릴은 버려도 되는 throwaway RDS로만(D6).
- `apply` 자체는 아무것도 fence/promote하지 않는다(리소스 정의만 추가).

### as-built 보정 (가이드와 의도적으로 다름)
- **서울 비번 로테이션 생략**(`SEOUL_DB_SECRET=""`) — 실제 서울 비번은 공유 시크릿 `farmily/prod/app`(JWT 등 다수 포함)뿐 + 로테이션 람다 없음. 공유 시크릿 로테이션은 위험 → **차단은 SG 교체만**(RotateSecret 권한도 미부여).
- **flip 파드 재시작 = TODO no-op** — 레포에 SSM/EKS 롤아웃 자동화가 아직 없음(greenfield). 좌표+시크릿 갱신까지만 하고, 읽기전용 해제는 후속(`ssm:SendCommand` 권한도 미부여).
- `verify`는 3-시크릿 접속(promoted=host/port · app-infra=user/name · app=password) — Phase 1 as-built과 동일.

### 적용 전 — 사전 준비
```bash
# verify 의존성(pg8000) 벤더링 — diagnose와 동일(미설치 시 zip에 모듈 누락)
pip install pg8000 -t lambdas/verify/
```

### 적용
```bash
cd environments/dr-brain
terraform plan     # ★ 검수: 신규 add + stepfunctions.tf(상태기계·정책) in-place change + 0 destroy
                   #   (Phase 3 placeholder를 실 체인으로 바꾸는 거라 state machine 1건 change는 정상)
terraform apply
```

### 검증 (apply 후)
```bash
# dry-run — fence·promote가 no-op으로 끝까지 흐르는지 (DryRunDone 도달)
aws stepfunctions start-execution --region ap-northeast-1 \
  --state-machine-arn $(aws stepfunctions list-state-machines --region ap-northeast-1 \
    --query "stateMachines[?name=='dr-brain-failover'].stateMachineArn" --output text) \
  --input '{"arm_promote": false}'
```
- [승인] → fence·promote no-op → `DryRunDone`으로 성공. fence 실패 주입 시 `FenceFailed`로 멈추고 **promote 미호출**.
- 진짜 promote 드릴은 **throwaway RDS**로만 `arm_promote=true`.

### FIS 게임데이 런북 (서울 리전 격리)
계정에 템플릿 **`Seoul-Region-Network-Disruption`**(`EXTXoynPL9KzRpt`, 서울 private 서브넷 2개, `PT15M`)이 이미 있다.
```bash
aws fis get-experiment-template --id EXTXoynPL9KzRpt --region ap-northeast-2   # 먼저 정의 확인
# ★ 상태기계 입력이 arm_promote=false 인지 반드시 먼저 확인 후:
aws fis start-experiment --experiment-template-id EXTXoynPL9KzRpt --region ap-northeast-2
```
> ⚠️ **15분 뒤 자동복구 ↔ auto-failback**: 이 템플릿은 15분 뒤 연결을 복구해 Route53이 트래픽을 서울로 되돌린다.
> 드릴(`arm_promote=false`)에선 안전(도쿄 미승격). **진짜 promote까지 했다면** 복귀한 서울이 다시 쓰기를 받아 split-brain →
> 서울 자동복귀를 막아야 함. 비상 정지: `aws fis stop-experiment --id <실행ID>`.

## 검증 완료 (Claude) — Phase 4
- `terraform fmt` 무변경(스타일 일치), `terraform validate` → **Success**
- 가이드 `dr-4` 코드 그대로 이식 + as-built 보정 3가지(위). `lambda_assume`·`aws.seoul` provider·`aws_iam_role.sfn` 재사용
- `stepfunctions.tf`는 Phase 3 파일을 교체(상태기계·정책 in-place) — 신규 리소스는 fence/promote/flip/verify 일습

---

## Phase 7 (검수 에이전트 — promote 직후 split-brain을 스스로 조사하는 AI 에이전트)

dr-7의 단발 verify_advisor를 **진짜 에이전트**로 올렸다. promote 직후, **읽기전용 도구를 스스로 골라가며 조사**한 뒤
split-brain 위험을 한국어로 판정한다. 단발 호출(워크플로우)이 아니라 **도구를 골라 도는 루프**라서 에이전트다.
**AgentCore 없이** Lambda 안에서 Bedrock Converse `tool-use` 루프로 구현. 가이드: `eks-infra/eks-dr/guide/dr-7-failover-audit.md`

### 추가/변경된 자산
- `lambdas/audit_agent/handler.py` — **검수 에이전트**(비-VPC, 표준 라이브러리). 읽기전용 도구 3개:
  `reprobe_seoul`(서울 재-probe)·`describe_rds`(dr-rds/prod-rds 상태)·`get_coordinator`(단일 writer). Converse 루프(최대 5턴).
- `audit_agent.tf` — 에이전트 람다 + IAM(`bedrock:InvokeModel`·`dynamodb:GetItem`·`rds:DescribeDBInstances`).
- `lambdas/verify/handler.py`(확장) — baseline 신호에 `in_recovery`·`audits{테이블:행수}` 추가(`AUDIT_TABLES`).
- `stepfunctions.tf` — `Verify → VerifyJudge(에이전트) → AuditGate → ok=Done / else=NotifyAndPage(SNS)→Done`.

### ★ 왜 '에이전트'이고 어디까지 안전한가
- **AI가 스스로 조사**: baseline만 받고 끝나는 게 아니라, *"서울을 다시 찔러봐야겠다 / RDS 상태를 보자"* 처럼
  **도구를 직접 골라 반복 조사**한 뒤 판정한다(자율 제어 루프 = 에이전트).
- **분기는 AI가 아니라 결정론적 Rule**: `rule_verdict`(ok/suspect/danger)는 핸들러의 `_rule()`이 baseline+좌표로
  계산한다. AI가 말을 바꾸거나 죽어도(`ai_unavailable`) **분기는 안 흔들린다**. AI는 조사·설명·권고만.
- **모든 도구 읽기전용**: promote·fence·복구 등 행동은 일절 안 한다. 비가역 동작 *뒤* + 비차단이라 안전.

### as-built / 결정
- `AUDIT_TABLES = "users,farm_diaries,subscriptions,payments"` — Backend V1 스키마 실재 핵심 테이블(신뢰 이름만, SQL 주입 방지).
- 좌표(단일 writer 신호)는 verify(VPC)가 아니라 **에이전트(비-VPC)가 직접** 읽음 → VPC 람다가 DynamoDB까지 닿을 필요 없음.
- dr-5(Retrospective) 미구현 → AuditGate/NotifyAndPage의 `Next=Done`. dr-5 추가 시 `Retrospective`로 재배선.
- 깊은 DB 포렌식(최신 레코드·시퀀스 연속성)은 VPC db-tool 람다 필요 → v2 후속.

### 검증 (apply 후)
```bash
# 에이전트를 합성 baseline(split-brain 의심 시나리오)으로 직접 호출 → 도구 루프가 도는지 + 판정 확인
aws lambda invoke --function-name dr-brain-audit-agent --region ap-northeast-1 \
  --payload '{"verify":{"writable":true,"in_recovery":false,"app_200":true,"audits":{}}}' \
  --cli-binary-format raw-in-base64-out a.json && cat a.json
# 기대: rule_verdict(좌표 기준)·tools_used(reprobe_seoul/describe_rds 등)·audit_ko(한국어 판정)
```

## 검증 완료 (Claude) — Phase 7
- `terraform fmt` 무변경, `terraform validate` → **Success**
- DIY Bedrock Converse tool-use 루프(AgentCore 미사용). `lambda_assume`·`coordinator`·`approvals`·`var.*` 재사용
- 분기=결정론 Rule, AI=조사·설명. 모든 도구 읽기전용 → advisory 원칙 유지

---

## Phase 5 (회고 — 실측 RTO/RPO를 AI가 한국어로)

failover가 끝나면 마지막에 **실측 RTO/RPO 회고 보고서**를 자동으로 남긴다. Step Functions가 단계마다 자동으로 찍은
타임스탬프(실행 히스토리)를 읽어 단계별 소요·총 RTO를 계산하고, Bedrock이 한국어로 정리해 S3에 쌓는다.
가이드: `eks-infra/eks-dr/guide/dr-5-retrospective.md`

### 추가/변경된 자산
- `lambdas/retrospective/handler.py` — 실행 히스토리(상태 진입 시각) + diagnose 복제지연(RPO 하한) + audit 판정을
  Bedrock에 넘겨 한국어 회고를 만들고 S3에 저장. 표준 라이브러리만(VPC·의존성 불필요). AI 죽어도 raw 타임라인은 남김.
- `retrospective.tf` — 전용 버킷 `dr-brain-retro-<account>`(공개차단) + 람다 + IAM(`states:GetExecutionHistory`·
  `bedrock:InvokeModel`·`s3:PutObject`).
- `stepfunctions.tf` 재배선 — `AuditGate(ok)`·`NotifyAndPage`를 `Done`→**`Retrospective`→`Done`**. 검수 결과가
  안전이든 의심이든 **어느 경로로 끝나도 회고는 남는다**. sfn 역할에 retrospective invoke 추가.

### 왜 거의 공짜인가
- 상태기계는 모든 상태 전환마다 타임스탬프를 히스토리에 자동으로 남긴다. 따로 계측 코드를 안 심어도 각 단계가 몇 초
  걸렸는지 그대로 나온다. 회고 람다는 히스토리를 읽어 AI에게 넘기기만 한다.
- 가이드보다 enrich: 타임라인(RTO)에 더해 diagnose 복제지연(RPO 하한)·audit 판정을 같이 넘겨 보고서가 더 충실하다.

### 검증 (apply 후)
```bash
# 실행 ARN 확보(기존 실행 없으면 start-execution — Slack 미설정이라 PostApproval에서 실패하지만 부분 히스토리는 남음, 무해)
ARN=$(aws stepfunctions list-executions --region ap-northeast-1 \
  --state-machine-arn $(aws stepfunctions list-state-machines --region ap-northeast-1 \
    --query "stateMachines[?name=='dr-brain-failover'].stateMachineArn" --output text) \
  --max-items 1 --query "executions[0].executionArn" --output text)
aws lambda invoke --function-name dr-brain-retrospective --region ap-northeast-1 \
  --payload "{\"executionArn\":\"$ARN\"}" --cli-binary-format raw-in-base64-out retro.json && cat retro.json
# 기대: report_ko(한국어 회고) + S3 dr-retro/<id>.md 적재(saved:true)
```

## 검증 완료 (Claude) — Phase 5
- `terraform fmt` 무변경, `terraform validate` → **Success**
- 단발형 회고(에이전트 아님 — 타임라인 읽어 요약이라 조건분기 없음). `lambda_assume`·`var.bedrock_model_id`·`data.aws_caller_identity` 재사용
- 상태기계 재배선(AuditGate/NotifyAndPage→Retrospective→Done)은 in-place change. 후속: RCA 회고 에이전트화(로그 적응형)
