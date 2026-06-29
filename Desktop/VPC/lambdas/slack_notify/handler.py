# lambdas/slack_notify/handler.py  —  승인 카드를 Slack에 띄운다
# 표준 라이브러리 + boto3(런타임 기본 제공)만 쓴다 — 의존성 zip 불필요, VPC 불필요.
# Step Functions의 PostApproval(waitForTaskToken)이 이 함수를 부르며 taskToken을 넘긴다.
import os, json, uuid, urllib.request, boto3

REGION = "ap-northeast-1"


def _post(bot_token, channel, blocks):
    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=json.dumps({"channel": channel, "blocks": blocks}).encode(),
        headers={"Authorization": f"Bearer {bot_token}", "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))


def handler(event, _ctx):
    sm  = boto3.client("secretsmanager", region_name=REGION)
    cfg = json.loads(sm.get_secret_value(SecretId=os.environ["SLACK_SECRET"])["SecretString"])
    token  = event["taskToken"]                       # Step Functions가 넣어줌
    advice = event.get("advice_ko", "(분석 없음)")
    # 실전 vs 테스트 — 실행 입력의 arm_promote(없거나 false면 테스트). 콜백까지 흘려보내 결과 피드백에 쓴다.
    mode = "armed" if event.get("arm_promote") else "dry"
    banner = ("🧪 *테스트 모드* (arm_promote=false) — 승인해도 실제 전환은 일어나지 않습니다."
              if mode == "dry" else
              "🔴 *실전 모드* (arm_promote=true) — 승인하면 실제 fence·promote가 진행됩니다.")

    # 토큰은 길어서 버튼 value(2000자 제한)에 직접 못 넣는다 → 짧은 id로 바꿔 DynamoDB에 보관.
    tid = str(uuid.uuid4())
    boto3.client("dynamodb", region_name=REGION).put_item(
        TableName=os.environ["TOKENS_TABLE"],
        Item={"id": {"S": tid}, "token": {"S": token}})

    blocks = [
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*🚨 서울 장애 — DR 판단 요청*\n{advice}\n\n{banner}"}},
        {"type": "actions", "elements": [
            {"type": "button", "style": "primary", "action_id": "approve",
             "text": {"type": "plain_text", "text": "승인 (Promote)"}, "value": f"approve:{tid}:{mode}"},
            {"type": "button", "style": "danger", "action_id": "reject",
             "text": {"type": "plain_text", "text": "거부"}, "value": f"reject:{tid}:{mode}"}]}]
    _post(cfg["bot_token"], cfg["channel"], blocks)
    return {"posted": True}
