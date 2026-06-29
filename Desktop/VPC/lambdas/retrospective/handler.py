# lambdas/retrospective/handler.py  —  실행 히스토리 → 한국어 회고 보고서 (Bedrock)
#
# failover가 끝나면, Step Functions가 단계마다 자동으로 남긴 타임스탬프(실행 히스토리)를 읽어
# "총 몇 분 걸렸고(RTO), 어디가 병목이었고, 얼마를 잃었나(RPO)"를 한국어로 정리해 S3에 쌓는다.
# 계측 코드를 따로 안 심어도 히스토리가 곧 회고 데이터다 — 이 함수는 그걸 읽어 AI에게 번역시킬 뿐.
# AI가 쓰이는 마지막 자리. Bedrock이 죽어도 raw 타임라인은 S3에 남긴다.
# 표준 라이브러리 + boto3(런타임 기본)만 — 의존성 zip·VPC 불필요.
import os, json, urllib.request, boto3

REGION = "ap-northeast-1"


def _timeline(events):
    # 상태 진입 시각만 추려 (상태명, ISO시각) 목록으로
    tl = []
    for e in events:
        d = e.get("stateEnteredEventDetails")
        if d and e.get("timestamp"):
            tl.append({"state": d["name"], "t": e["timestamp"].isoformat()})
    return tl


def _confirm(text):                                    # 버튼 클릭 시 확인 다이얼로그(오클릭 방지)
    return {"title": {"type": "plain_text", "text": "정말 실행할까요?"},
            "text": {"type": "mrkdwn", "text": text},
            "confirm": {"type": "plain_text", "text": "실행"},
            "deny": {"type": "plain_text", "text": "취소"}}


def _slack_report(report, bucket, key):
    # 회고 보고서를 Slack에 게시 + 복구 버튼(unfence/pin/unpin)을 단다. best-effort(실패해도 무방).
    # 버튼 클릭은 slack_callback이 받아 해당 Lambda를 직접 호출한다(승인 토큰 흐름과 별개).
    sid = os.environ.get("SLACK_SECRET", "")
    if not sid:
        return False
    try:
        cfg = json.loads(boto3.client("secretsmanager", region_name=REGION)
                         .get_secret_value(SecretId=sid)["SecretString"])
        body = report if len(report) <= 2800 else report[:2800] + "\n…(생략 — 전문은 S3)"
        blocks = [
            {"type": "section", "text": {"type": "mrkdwn", "text": f"*📋 DR Failover 회고 보고서*\n{body}"}},
            {"type": "context", "elements": [{"type": "mrkdwn", "text": f"전문: `s3://{bucket}/{key}`"}]},
            {"type": "actions", "elements": [
                {"type": "button", "style": "primary", "action_id": "unfence", "value": "unfence",
                 "text": {"type": "plain_text", "text": "서울 DB 복구 (unfence)"},
                 "confirm": _confirm("서울 prod-rds의 보안그룹을 원래대로 되돌립니다. *실전 promote 후라면 split-brain 위험* — '이건 드릴이었다'고 확신할 때만.")},
                {"type": "button", "action_id": "pin", "value": "pin",
                 "text": {"type": "plain_text", "text": "트래픽 도쿄 고정 (pin)"},
                 "confirm": _confirm("서울 health check를 죽여 사용자 트래픽을 도쿄에 묶습니다(FIS 자동복구로 서울 복귀 방지).")},
                {"type": "button", "action_id": "unpin", "value": "unpin",
                 "text": {"type": "plain_text", "text": "트래픽 해제 (unpin)"},
                 "confirm": _confirm("트래픽 고정을 풀어 정상 health 기반 failover로 되돌립니다.")},
            ]},
        ]
        req = urllib.request.Request(
            "https://slack.com/api/chat.postMessage",
            data=json.dumps({"channel": cfg["channel"], "blocks": blocks}).encode(),
            headers={"Authorization": f"Bearer {cfg['bot_token']}", "Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=5)
        return True
    except Exception:
        return False


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
            inferenceConfig={"maxTokens": 4000, "temperature": 0.3})
        report = r["output"]["message"]["content"][0]["text"]
    except Exception as e:
        # AI가 죽어도 raw 타임라인은 남긴다(회고의 원재료)
        report = (f"(AI 회고 생성 불가: {e})\n\n[원본 타임라인]\n"
                  + json.dumps(timeline, ensure_ascii=False, indent=2))

    key = f"dr-retro/{arn.split(':')[-1] or 'manual'}.md"
    saved, err = True, None
    try:
        boto3.client("s3", region_name=REGION).put_object(
            Bucket=os.environ["REPORT_BUCKET"], Key=key, Body=report.encode("utf-8"))
    except Exception as e:
        saved, err = False, str(e)[:120]

    slacked = _slack_report(report, os.environ.get("REPORT_BUCKET", ""), key)  # S3 + Slack 양쪽
    out = {"report_ko": report, "saved": saved, "s3_key": key, "slacked": slacked}
    if err:
        out["error"] = err
    return out
