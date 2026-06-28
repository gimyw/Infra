# lambdas/verify/handler.py  —  검수 baseline 신호를 모은다 (dr-7 확장)
# 새 primary에 실제로 써보고(스모크), 복구 모드가 아닌지 확인하고, 앱 200·핵심 테이블 상태를 본다.
# verify가 빨간불이어도 promote는 되돌리지 않는다 — 사실 확인이 목적이고, 실패는 숨기지 않고 알린다.
# 여기서 모은 신호를 audit_agent(검수 에이전트)가 받아 split-brain을 판정한다. (단일 writer 신호=좌표는
# audit_agent가 직접 읽으므로 verify엔 안 넣는다 → VPC 람다가 DynamoDB까지 닿을 필요 없음.)
#   접속 정보는 diagnose와 같은 3원천:
#     PROMOTED_SECRET (farmily/dr/promoted-db) : DB_HOST, DB_PORT (flip이 기록한 새 쓰기 엔드포인트)
#     DB_SECRET       (farmily/dr/app-infra)   : DB_USER(farmilyadmin), DB_NAME
#     DB_APP_SECRET   (farmily/dr/app)         : DB_PASSWORD
import os, json, urllib.request, boto3, pg8000.native

REGION = "ap-northeast-1"


def handler(event, _ctx):
    sm    = boto3.client("secretsmanager", region_name=REGION)
    prom  = json.loads(sm.get_secret_value(SecretId=os.environ["PROMOTED_SECRET"])["SecretString"])
    infra = json.loads(sm.get_secret_value(SecretId=os.environ["DB_SECRET"])["SecretString"])
    app   = json.loads(sm.get_secret_value(SecretId=os.environ["DB_APP_SECRET"])["SecretString"])
    c = pg8000.native.Connection(
        host=prom["DB_HOST"], port=int(prom.get("DB_PORT", 5432)),
        user=infra["DB_USER"], password=app["DB_PASSWORD"],
        database=infra.get("DB_NAME", "postgres"), ssl_context=True)

    in_recovery = bool(c.run("SELECT pg_is_in_recovery()")[0][0])  # promote 됐으면 False
    writable = True
    try:
        c.run("CREATE TEMP TABLE _dr_smoke(x int); INSERT INTO _dr_smoke VALUES (1)")  # 쓰기 가능?
    except Exception:
        writable = False

    # 핵심 테이블 정합성 — AUDIT_TABLES는 운영자가 지정하는 신뢰된 이름만(사용자 입력 X, SQL 주입 방지)
    audits = {}
    for t in [x.strip() for x in os.environ.get("AUDIT_TABLES", "").split(",") if x.strip()]:
        try:
            audits[t] = {"rows": int(c.run(f"SELECT count(*) FROM {t}")[0][0])}
        except Exception as e:
            audits[t] = {"error": str(e)[:80]}

    health = False
    try:
        with urllib.request.urlopen("https://api.farmily.info/api/v1/health", timeout=4) as r:
            health = (r.status == 200)
    except Exception:
        pass

    return {"writable": writable and not in_recovery, "in_recovery": in_recovery,
            "app_200": health, "audits": audits}
