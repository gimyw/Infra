# lambdas/slack_callback/handler.py  —  버튼 클릭을 받아 멈춘 흐름을 재개한다
# Lambda Function URL 뒤에 붙는다(공개 HTTPS). 인증은 Slack 서명검증으로 이 안에서 한다.
# 표준 라이브러리 + boto3만 쓴다 — 의존성 zip 불필요, VPC 불필요.
import os, json, hmac, hashlib, time, base64, urllib.parse, boto3

REGION = "ap-northeast-1"


def _verify(headers, raw_body, secret):
    ts = headers.get("x-slack-request-timestamp", "0")
    if abs(time.time() - int(ts)) > 300:               # 5분 지난 요청은 거부(재전송 공격 방지)
        return False
    base = f"v0:{ts}:{raw_body}".encode()
    mine = "v0=" + hmac.new(secret.encode(), base, hashlib.sha256).hexdigest()
    return hmac.compare_digest(mine, headers.get("x-slack-signature", ""))


def handler(event, _ctx):
    sm  = boto3.client("secretsmanager", region_name=REGION)
    cfg = json.loads(sm.get_secret_value(SecretId=os.environ["SLACK_SECRET"])["SecretString"])

    # Function URL이 본문을 base64로 줄 수 있다 → 서명검증·parse 이전에 raw 문자열로 되돌린다.
    body = event.get("body", "")
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode()

    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if not _verify(headers, body, cfg["signing_secret"]):
        return {"statusCode": 401, "body": "bad signature"}

    payload = json.loads(urllib.parse.parse_qs(body)["payload"][0])
    decision, tid = payload["actions"][0]["value"].split(":", 1)   # approve:tid / reject:tid

    ddb  = boto3.client("dynamodb", region_name=REGION)
    item = ddb.get_item(TableName=os.environ["TOKENS_TABLE"], Key={"id": {"S": tid}}).get("Item")
    if not item:
        return {"statusCode": 200, "body": "이미 처리된 요청입니다"}
    token = item["token"]["S"]

    # 토큰만 돌려주고 즉시 200(Slack은 3초 안에 응답을 기대). 실제 fence/promote는
    # 흐름이 재개된 뒤 Step Functions의 별도 단계에서 한다 — 콜백은 "문을 여는" 일만.
    boto3.client("stepfunctions", region_name=REGION).send_task_success(
        taskToken=token, output=json.dumps({"approved": decision == "approve"}))
    ddb.delete_item(TableName=os.environ["TOKENS_TABLE"], Key={"id": {"S": tid}})
    return {"statusCode": 200, "body": "승인됨 ✅" if decision == "approve" else "거부됨 ❌"}
