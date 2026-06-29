# lambdas/slack_callback/handler.py  —  버튼 클릭을 받아 멈춘 흐름을 재개한다
# API Gateway HTTP API 뒤에 붙는다(공개 HTTPS). 인증은 Slack 서명검증으로 이 안에서 한다.
# 표준 라이브러리 + boto3만 쓴다 — 의존성 zip 불필요, VPC 불필요.
import os, json, hmac, hashlib, time, base64, urllib.parse, urllib.request, boto3

REGION = "ap-northeast-1"


def _verify(headers, raw_body, secret):
    ts = headers.get("x-slack-request-timestamp", "0")
    if abs(time.time() - int(ts)) > 300:               # 5분 지난 요청은 거부(재전송 공격 방지)
        return False
    base = f"v0:{ts}:{raw_body}".encode()
    mine = "v0=" + hmac.new(secret.encode(), base, hashlib.sha256).hexdigest()
    return hmac.compare_digest(mine, headers.get("x-slack-signature", ""))


def _replace_card(response_url, text):
    # 버튼 클릭 뒤 원본 카드를 이 문구로 교체한다(버튼이 사라져 연타·중복클릭 방지 + 결과 피드백).
    # response_url은 Slack이 클릭 페이로드에 담아 보내며 30분간 유효. 실패해도 흐름엔 영향 없다.
    if not response_url:
        return
    try:
        req = urllib.request.Request(
            response_url,
            data=json.dumps({"replace_original": True, "text": text}).encode(),
            headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=3)
    except Exception:
        pass


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
    response_url = payload.get("response_url")          # 원본 카드를 교체할 때 쓴다(클릭마다 Slack이 줌)
    parts = payload["actions"][0]["value"].split(":")   # approve:tid:mode / reject:tid:mode
    decision, tid = parts[0], parts[1]
    mode = parts[2] if len(parts) > 2 else "dry"        # 구버전 카드(value 2조각) 대비 기본 dry

    ddb  = boto3.client("dynamodb", region_name=REGION)
    item = ddb.get_item(TableName=os.environ["TOKENS_TABLE"], Key={"id": {"S": tid}}).get("Item")
    if not item:                                        # 이미 처리된 요청(연타·중복) — 카드만 정리
        _replace_card(response_url, "이미 처리된 요청입니다.")
        return {"statusCode": 200, "body": "already processed"}
    token = item["token"]["S"]

    # 토큰만 돌려주고 즉시 200(Slack은 3초 안에 응답을 기대). 실제 fence/promote는
    # 흐름이 재개된 뒤 Step Functions의 별도 단계에서 한다 — 콜백은 "문을 여는" 일만.
    boto3.client("stepfunctions", region_name=REGION).send_task_success(
        taskToken=token, output=json.dumps({"approved": decision == "approve"}))
    ddb.delete_item(TableName=os.environ["TOKENS_TABLE"], Key={"id": {"S": tid}})

    # 카드를 결과 문구로 교체 — 버튼이 사라지고, 테스트/실전 모드까지 보인다.
    if decision == "approve":
        result = ("✅ 승인됨 (테스트 모드) — 흐름만 검증하고 실제 전환은 없습니다."
                  if mode == "dry" else
                  "✅ 승인됨 (실전) — 실제 fence·promote를 진행합니다.")
    else:
        result = "❌ 거부됨 — 전환을 취소했습니다."
    _replace_card(response_url, result)
    return {"statusCode": 200, "body": "ok"}
