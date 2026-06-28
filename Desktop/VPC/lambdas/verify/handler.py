# lambdas/verify/handler.py  —  정말 됐는지 확인한다
# 새 primary에 실제로 써보고(스모크), 더 이상 복구 모드가 아닌지 확인하고, 앱이 200을 주는지 본다.
# verify가 빨간불이어도 promote는 되돌리지 않는다 — 사실 확인이 목적이고, 실패는 숨기지 않고 알린다.
# (정합성 신호 확장·split-brain 판정은 dr-7에서 이 파일을 넓힌다.)
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

    in_recovery = c.run("SELECT pg_is_in_recovery()")[0][0]      # promote 됐으면 False
    c.run("CREATE TEMP TABLE _dr_smoke(x int); INSERT INTO _dr_smoke VALUES (1)")  # 쓰기 가능?

    health = False
    try:
        with urllib.request.urlopen("https://api.farmily.info/api/v1/health", timeout=4) as r:
            health = (r.status == 200)
    except Exception:
        pass

    return {"writable": not in_recovery, "app_200": health}
