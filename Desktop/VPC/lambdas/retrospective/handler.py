# lambdas/retrospective/handler.py  —  실행 히스토리 → 한국어 회고 보고서 (Bedrock)
#
# failover가 끝나면, Step Functions가 단계마다 자동으로 남긴 타임스탬프(실행 히스토리)를 읽어
# "총 몇 분 걸렸고(RTO), 어디가 병목이었고, 얼마를 잃었나(RPO)"를 한국어로 정리해 S3에 쌓는다.
# 계측 코드를 따로 안 심어도 히스토리가 곧 회고 데이터다 — 이 함수는 그걸 읽어 AI에게 번역시킬 뿐.
# AI가 쓰이는 마지막 자리. Bedrock이 죽어도 raw 타임라인은 S3에 남긴다.
# 표준 라이브러리 + boto3(런타임 기본)만 — 의존성 zip·VPC 불필요.
import os, json, boto3

REGION = "ap-northeast-1"


def _timeline(events):
    # 상태 진입 시각만 추려 (상태명, ISO시각) 목록으로
    tl = []
    for e in events:
        d = e.get("stateEnteredEventDetails")
        if d and e.get("timestamp"):
            tl.append({"state": d["name"], "t": e["timestamp"].isoformat()})
    return tl


def handler(event, _ctx):
    arn = event.get("executionArn", "")
    diagnose = event.get("diagnose", {}) or {}
    audit = event.get("audit", {}) or {}

    sf = boto3.client("stepfunctions", region_name=REGION)
    try:
        events = sf.get_execution_history(executionArn=arn, maxResults=1000)["events"]
        timeline = _timeline(events)
    except Exception as e:
        timeline = []
        diagnose = {**diagnose, "_history_error": str(e)[:120]}

    prompt = (
        "다음은 DR failover 실행의 단계별 진입 시각과 부가 신호다.\n"
        f"- 타임라인(상태 진입 시각): {json.dumps(timeline, ensure_ascii=False)}\n"
        f"- 진단(복제 지연 등): {json.dumps(diagnose, ensure_ascii=False)}\n"
        f"- 검수 판정: rule_verdict={audit.get('rule_verdict')}\n\n"
        "아래를 한국어 회고 보고서로 써라.\n"
        "1) 단계별 소요 시간과 총 RTO(탐지~검증)\n"
        "2) 사람 승인(PostApproval)이 차지한 비중 = 최대 병목인지\n"
        "3) 추정 RPO 하한 — 진단의 복제 지연(lag_s) 기준, 서울 미도달 시 정확값 불가임을 명시\n"
        "4) 검수 결과(rule_verdict) 한 줄\n"
        "5) 개선점(예: 사전 승인 정책으로 승인 병목 단축, promote는 RDS 관리형 한계)"
    )

    report = None
    try:
        r = boto3.client("bedrock-runtime", region_name=REGION).converse(
            modelId=os.environ["MODEL_ID"],
            messages=[{"role": "user", "content": [{"text": prompt}]}],
            inferenceConfig={"maxTokens": 1500, "temperature": 0.3})
        report = r["output"]["message"]["content"][0]["text"]
    except Exception as e:
        # AI가 죽어도 raw 타임라인은 남긴다(회고의 원재료)
        report = (f"(AI 회고 생성 불가: {e})\n\n[원본 타임라인]\n"
                  + json.dumps(timeline, ensure_ascii=False, indent=2))

    key = f"dr-retro/{arn.split(':')[-1] or 'manual'}.md"
    try:
        boto3.client("s3", region_name=REGION).put_object(
            Bucket=os.environ["REPORT_BUCKET"], Key=key, Body=report.encode("utf-8"))
    except Exception as e:
        return {"report_ko": report, "saved": False, "error": str(e)[:120]}
    return {"report_ko": report, "saved": True, "s3_key": key}
