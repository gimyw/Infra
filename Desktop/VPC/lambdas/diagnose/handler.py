# lambdas/diagnose/handler.py — 도쿄 replica의 복제 지연을 읽는다 (읽기 전용)
#   접속 정보는 두 시크릿에서 모은다(둘 다 이미 존재):
#     farmily/dr/app-infra : DB_HOST, DB_PORT, DB_USER(farmilyadmin), DB_NAME
#     farmily/dr/app       : DB_PASSWORD
#   farmilyadmin은 마스터 계정이라 복제 상태 함수 호출 가능(별도 모니터 계정 불필요).
import json, os, boto3, pg8000.native

REGION = "ap-northeast-1"            # 도쿄 고정


def _conn():
    sm = boto3.client("secretsmanager", region_name=REGION)
    infra = json.loads(sm.get_secret_value(SecretId=os.environ["DB_SECRET"])["SecretString"])
    app = json.loads(sm.get_secret_value(SecretId=os.environ["DB_APP_SECRET"])["SecretString"])
    return pg8000.native.Connection(
        host=infra["DB_HOST"], port=int(infra.get("DB_PORT", 5432)),
        user=infra["DB_USER"], password=app["DB_PASSWORD"],
        database=infra.get("DB_NAME", "postgres"), ssl_context=True,
    )


def handler(event, _ctx):
    c = _conn()
    recv, replay = c.run("SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()")[0]
    lag_s = c.run("SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))")[0][0]
    backlog = c.run("SELECT pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())")[0][0]
    in_recovery = c.run("SELECT pg_is_in_recovery()")[0][0]

    lag_s = float(lag_s or 0)
    tier = "LOW" if lag_s < 5 else "MED" if lag_s <= 30 else "HIGH"
    return {
        "lag_s": round(lag_s, 1),
        "apply_backlog_bytes": int(backlog or 0),
        "recv_lsn": str(recv), "replay_lsn": str(replay),
        "is_replica": bool(in_recovery),   # 평소엔 True, promote 후 False
        "risk_tier": tier,
    }
