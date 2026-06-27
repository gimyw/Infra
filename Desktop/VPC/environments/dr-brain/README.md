# dr-brain — Phase 1 (diagnose + advisor)

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
