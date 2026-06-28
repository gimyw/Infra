# lambdas/verify/handler.py  —  검수 DB 워커 (이중 모드, dr-7 v2)
#
# 두 가지로 쓰인다(같은 람다, 페이로드로 분기):
#   1) baseline 모드 (event에 check 없음) — Step Functions의 Verify 단계가 호출. 승격 직후 핵심 신호를
#      결정론적으로 한 번에 수집. seq_ok(시퀀스 정합)은 audit_agent의 분기 게이트로 쓰인다.
#   2) check 모드   (event에 check) — audit_agent(검수 에이전트)가 도구로 호출. 명명된 읽기전용 검사 1개.
#      에이전트가 "방금 본 걸 보고" 어떤 검사를 돌릴지 스스로 고른다(조건분기 포렌식).
#
# 안전: 전부 읽기전용 SELECT. 화이트리스트 테이블/관계만(자유 SQL 금지). 접속 직후 statement_timeout=3s로
#       어떤 쿼리도 DB를 오래 붙잡지 못하게 한다(장애 중 부하 금지). 모든 검사는 빠른 형태(인덱스 max·EXISTS·추정).
#   접속 정보(diagnose와 같은 3원천, host는 promoted 우선·없으면 app-infra=dr-rds 고정 엔드포인트로 fallback):
#     PROMOTED_SECRET (farmily/dr/promoted-db) : DB_HOST, DB_PORT (flip이 기록한 새 쓰기 엔드포인트, 있으면)
#     DB_SECRET       (farmily/dr/app-infra)   : DB_HOST(dr-rds), DB_USER(farmilyadmin), DB_NAME
#     DB_APP_SECRET   (farmily/dr/app)         : DB_PASSWORD
import os, json, urllib.request, boto3, pg8000.native

REGION = "ap-northeast-1"

# 화이트리스트 — 신뢰된 이름만 SQL에 들어간다 (사용자/모델 입력을 SQL에 직접 안 씀)
IDENTITY_TABLES = ["users", "farm_diaries", "payments", "content_jobs"]   # BIGINT IDENTITY (시퀀스 있음)
AUDIT_TABLES    = ["users", "farm_diaries", "subscriptions", "payments", "content_jobs"]
TS_COL          = {"users": "updated_at", "farm_diaries": "updated_at", "payments": "created_at",
                   "subscriptions": "updated_at", "content_jobs": "created_at"}
# 고아 검사용 관계: (자식, FK컬럼, 부모, 부모PK)
RELATIONS = {
    "farm_diaries": ("farm_diaries", "user_id", "users", "id"),
    "subscriptions": ("subscriptions", "user_id", "users", "id"),
    "payments": ("payments", "user_id", "users", "id"),
    "content_jobs": ("content_jobs", "user_id", "users", "id"),
}


def _connect():
    sm  = boto3.client("secretsmanager", region_name=REGION)
    infra = json.loads(sm.get_secret_value(SecretId=os.environ["DB_SECRET"])["SecretString"])
    app   = json.loads(sm.get_secret_value(SecretId=os.environ["DB_APP_SECRET"])["SecretString"])
    host, port = infra["DB_HOST"], int(infra.get("DB_PORT", 5432))   # dr-rds 고정 엔드포인트(fallback 기본)
    prom_id = os.environ.get("PROMOTED_SECRET")
    if prom_id:
        try:
            prom = json.loads(sm.get_secret_value(SecretId=prom_id)["SecretString"])
            if prom.get("DB_HOST"):
                host, port = prom["DB_HOST"], int(prom.get("DB_PORT", 5432))
        except Exception:
            pass                                                     # promoted 없으면 dr-rds로
    c = pg8000.native.Connection(
        host=host, port=port, user=infra["DB_USER"], password=app["DB_PASSWORD"],
        database=infra.get("DB_NAME", "postgres"), ssl_context=True)
    c.run("SET statement_timeout = '3000ms'")                        # 어떤 쿼리도 3초 넘기면 중단
    return c


def _seq_check(c, table):
    # 시퀀스 last_value 가 max(id) 보다 작으면 다음 INSERT 가 PK 충돌(승격 직후 고전 함정)
    seq = c.run("SELECT pg_get_serial_sequence(:t, 'id')", t=table)[0][0]
    if not seq:
        return {"table": table, "skipped": "no identity sequence"}
    mx  = c.run(f"SELECT max(id) FROM {table}")[0][0] or 0
    lv  = c.run(f"SELECT last_value FROM {seq}")[0][0] or 0
    return {"table": table, "max_id": int(mx), "seq_last": int(lv), "ok": int(lv) >= int(mx)}


# ── check 모드: 명명된 읽기전용 검사들 ─────────────────────────
def _check_seq_gap(c, table):
    return _seq_check(c, table)


def _check_recency(c, table):
    col = TS_COL.get(table, "created_at")
    v = c.run(f"SELECT max({col}) FROM {table}")[0][0]
    return {"table": table, "column": col, "latest": str(v) if v else None}


def _check_orphans(c, relation):
    rel = RELATIONS.get(relation)
    if not rel:
        return {"error": f"unknown relation {relation}"}
    child, fk, parent, pk = rel
    has = c.run(f"SELECT EXISTS(SELECT 1 FROM {child} ch LEFT JOIN {parent} pa "
                f"ON ch.{fk} = pa.{pk} WHERE pa.{pk} IS NULL)")[0][0]
    return {"relation": relation, "orphans_exist": bool(has)}


def _check_rowcount(c, table):
    est = c.run("SELECT reltuples::bigint FROM pg_class WHERE relname = :t", t=table)[0][0]
    return {"table": table, "est_rows": int(est or 0)}


def _check_connections(c, _table):
    # 앱이 새 primary 에 실제로 붙었나(flip+파드재시작이 끝까지 됐는지)
    total  = c.run("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() "
                   "AND pid <> pg_backend_pid()")[0][0]
    active = c.run("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() "
                   "AND pid <> pg_backend_pid() AND state = 'active'")[0][0]
    return {"connections_total": int(total), "active": int(active)}


def _check_billing(c, _table):
    # 도메인 불변식(금전). status 문자열은 코드 기준 추정 → best-effort.
    pay_orphan = c.run("SELECT EXISTS(SELECT 1 FROM payments p LEFT JOIN subscriptions s "
                       "ON p.user_id = s.user_id WHERE s.user_id IS NULL)")[0][0]
    expired = c.run("SELECT count(*) FROM subscriptions "
                    "WHERE status = 'ACTIVE' AND current_period_end < now()")[0][0]
    return {"payments_without_subscription": bool(pay_orphan), "active_but_expired_subs": int(expired)}


CHECKS = {
    "seq_gap": _check_seq_gap, "recency": _check_recency, "orphans": _check_orphans,
    "rowcount": _check_rowcount, "connections": _check_connections, "billing": _check_billing,
}
# 인자 종류: relation 화이트리스트(orphans) / table 화이트리스트(나머지) / 무인자(connections·billing)
_REL_CHECKS, _NOARG_CHECKS = {"orphans"}, {"connections", "billing"}


def handler(event, _ctx):
    check = event.get("check")

    # ── check 모드 ──
    if check:
        fn = CHECKS.get(check)
        if not fn:
            return {"error": f"unknown check {check}"}
        arg = event.get("table") or event.get("relation")
        if check in _REL_CHECKS and arg not in RELATIONS:
            return {"error": f"relation not allowed: {arg}"}
        if check not in _REL_CHECKS and check not in _NOARG_CHECKS and arg not in AUDIT_TABLES:
            return {"error": f"table not allowed: {arg}"}
        try:
            c = _connect()
            return {"check": check, "arg": arg, "result": fn(c, arg)}
        except Exception as e:
            return {"check": check, "arg": arg, "error": str(e)[:160]}

    # ── baseline 모드 ──
    c = _connect()
    in_recovery = bool(c.run("SELECT pg_is_in_recovery()")[0][0])    # promote 됐으면 False
    writable = True
    try:
        c.run("CREATE TEMP TABLE _dr_smoke(x int); INSERT INTO _dr_smoke VALUES (1)")  # 쓰기 가능?
    except Exception:
        writable = False

    audits = {}
    for t in [x.strip() for x in os.environ.get("AUDIT_TABLES", "").split(",") if x.strip()]:
        try:
            audits[t] = {"rows": int(c.run("SELECT reltuples::bigint FROM pg_class WHERE relname = :t", t=t)[0][0] or 0)}
        except Exception as e:
            audits[t] = {"error": str(e)[:80]}

    seq_detail, seq_ok = [], True                                   # 시퀀스 정합(분기 게이트)
    for t in IDENTITY_TABLES:
        try:
            d = _seq_check(c, t)
            seq_detail.append(d)
            if d.get("ok") is False:
                seq_ok = False
        except Exception as e:
            seq_detail.append({"table": t, "error": str(e)[:80]})   # 에러는 게이트 안 건드림(skip)

    health = False
    try:
        with urllib.request.urlopen("https://api.farmily.info/api/v1/health", timeout=4) as r:
            health = (r.status == 200)
    except Exception:
        pass

    return {"writable": writable and not in_recovery, "in_recovery": in_recovery,
            "app_200": health, "audits": audits, "seq_ok": seq_ok, "seq_detail": seq_detail}
