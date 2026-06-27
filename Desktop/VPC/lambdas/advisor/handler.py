# lambdas/advisor/handler.py — 진단 숫자 -> 한국어 판단 (Bedrock, ADVISORY)
import os, boto3

REGION = "ap-northeast-1"
MODEL_ID = os.environ["MODEL_ID"]   # 도쿄 추론 프로파일 ID (예: jp.anthropic.claude-sonnet-4-6)

SYSTEM = (
    "너는 AWS 멀티리전 DR 운영 보조다. 절대 명령을 실행하지 않고, "
    "주어진 복제 지표만으로 운영자가 읽을 한국어 판단 자료를 만든다. "
    "추측은 '추정'으로 표시하고, promote가 비가역임을 항상 명시한다."
)

PROMPT = """다음은 도쿄 DR replica의 복제 상태다.

- 복제 지연: {lag_s}초 (등급 {risk_tier})
- 밀린 양(미반영): {apply_backlog_bytes} bytes
- 서울 health: {seoul_health}

아래 5가지를 한국어로, 군더더기 없이 써라.
1) 위험도 한 줄  2) 예상 데이터 손실(RPO 하한, 서울이 안 닿으면 정확값 불가임을 명시)
3) Failover 권고 여부와 근거  4) 운영자 절차(promote->검증->엔드포인트 교체)
5) 되돌릴 수 없다는 경고 한 줄"""


def handler(event, _ctx):
    d = event.get("diagnose", event)          # diagnose 출력 그대로 받음
    prompt = PROMPT.format(
        lag_s=d.get("lag_s"), risk_tier=d.get("risk_tier"),
        apply_backlog_bytes=d.get("apply_backlog_bytes"),
        seoul_health=event.get("seoul_health", "3회 연속 실패"),
    )
    br = boto3.client("bedrock-runtime", region_name=REGION)
    try:
        r = br.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM}],
            messages=[{"role": "user", "content": [{"text": prompt}]}],
            inferenceConfig={"maxTokens": 1200, "temperature": 0.2},
        )
        return {"advice_ko": r["output"]["message"]["content"][0]["text"],
                "ai_unavailable": False}
    except Exception as e:                      # AI가 죽어도 흐름은 안 막는다
        return {"advice_ko": f"(AI 분석 불가: {e}) 숫자만 보고 사람이 판단할 것.",
                "ai_unavailable": True}
