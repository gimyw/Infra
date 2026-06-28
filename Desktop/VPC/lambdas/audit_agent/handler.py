# lambdas/audit_agent/handler.py  —  Failover 검수 에이전트 (Bedrock Converse tool-use 루프, v2)
#
# promote 직후, split-brain/정합성을 '스스로 조사'하는 읽기전용 에이전트다.
# 단발 호출이 아니라 도구를 골라가며 도는 루프라서 워크플로우가 아니라 '에이전트'다 —
# 도구를 '무엇을·몇 번·어떤 순서로' 쓸지를 코드가 아니라 모델이 런타임에 정한다(제어권이 모델에).
#   - 도구 6종은 전부 읽기전용. 행동(promote·fence·복구) 절대 안 함.
#   - 분기(rule_verdict)는 AI가 아니라 결정론적 _rule()이 정한다(AI가 죽어도 분기는 안 흔들림).
#   - AI는 그 위에서 조사·설명·권고만 — 마지막에 RPO 추정·검수 커버리지·권고 런북을 한국어로 쓴다.
# 표준 라이브러리 + boto3(런타임 기본)만 — 의존성 zip·VPC 불필요.
import os, json, ssl, datetime, urllib.request, boto3

REGION, SEOUL = "ap-northeast-1", "ap-northeast-2"
MODEL_ID    = os.environ["MODEL_ID"]
TABLE       = os.environ["COORDINATOR_TABLE"]
HEALTH_URL  = os.environ["SEOUL_HEALTH_URL"]
DR_RDS_ID   = os.environ.get("DR_RDS_ID", "dr-rds")
PROD_RDS_ID = os.environ.get("PROD_RDS_ID", "prod-rds")
VERIFY_FN   = os.environ.get("VERIFY_FUNCTION", "dr-brain-verify")
FENCE_SG_ID = os.environ.get("FENCE_SG_ID", "")
S3_SRC      = os.environ.get("S3_SOURCE_BUCKET", "")
S3_DST      = os.environ.get("S3_DEST_BUCKET", "")
MAX_TURNS   = 10

SYSTEM = (
    "너는 DR failover 검수관 에이전트다. promote 직후 새 주 DB(도쿄)가 split-brain 없이 제대로 섰는지 조사한다. "
    "baseline 신호로 출발해, 필요하면 읽기전용 도구로 직접 더 캔다 — 무엇을 더 볼지는 방금 본 결과를 보고 네가 정한다. "
    "예: 서울이 살아있어 보이면 fence가 실제로 됐는지(check_fence) 확인하고, 데이터가 의심되면 run_db_check로 "
    "시퀀스·고아·결제 정합을 캔다. 절대 아무것도 실행·변경하지 않는다(읽기만). 확실치 않으면 보수적으로(의심) 본다. "
    "전체 테이블 스캔 같은 무거운 쿼리는 시키지 마라(도구가 이미 빠른 형태로 제한돼 있다). "
    "충분히 조사했으면 한국어로 다음을 쓴다: "
    "① 종합 판정(안전/의심/분열 징후) ② 근거(어떤 신호가 정상/이상) ③ 운영자 권고 액션(구체 명령 포함, 예: "
    "시퀀스가 뒤처졌으면 ALTER SEQUENCE ... RESTART WITH ...) ④ RPO 추정(최신성·복제 지연 기반, 하한) "
    "⑤ 검수 커버리지(무엇을 봤고, 무엇은 못 봤는지 — 예: 서울 DB 직접 비교 불가, S3 복제 메트릭 미활성). "
    "'도쿄가 유일한 writer'여야 안전하다 — 서울이 아직 서빙하거나 fence가 안 끝났으면 분열 위험이다."
)

_NOVERIFY = ssl._create_unverified_context()


# ── 읽기전용 도구 6종 ─────────────────────────────────────────
def _reprobe_seoul(_a):
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=4, context=_NOVERIFY) as r:
            return {"seoul_health_ok": r.status == 200, "status": r.status}
    except Exception as e:
        return {"seoul_health_ok": False, "error": str(e)[:120]}


def _describe_rds(a):
    which = (a or {}).get("which", "dr")
    ident, region = (DR_RDS_ID, REGION) if which == "dr" else (PROD_RDS_ID, SEOUL)
    try:
        d = boto3.client("rds", region_name=region).describe_db_instances(
            DBInstanceIdentifier=ident)["DBInstances"][0]
        return {"identifier": ident, "region": region, "status": d.get("DBInstanceStatus"),
                "is_read_replica": bool(d.get("ReadReplicaSourceDBInstanceIdentifier")),
                "source": d.get("ReadReplicaSourceDBInstanceIdentifier")}
    except Exception as e:
        return {"identifier": ident, "region": region, "error": str(e)[:120]}


def _get_coordinator(_a):
    try:
        return _coord(boto3.client("dynamodb", region_name=REGION).get_item(
            TableName=TABLE, Key={"key": {"S": "primary"}}).get("Item", {}))
    except Exception as e:
        return {"error": str(e)[:120]}


def _run_db_check(a):
    # verify를 check 모드로 호출(읽기전용 정합성 쿼리). 어떤 검사를 돌릴지는 모델이 고른다.
    payload = {"check": (a or {}).get("check"), "table": (a or {}).get("table")}
    try:
        r = boto3.client("lambda", region_name=REGION).invoke(
            FunctionName=VERIFY_FN, Payload=json.dumps(payload).encode())
        return json.loads(r["Payload"].read())
    except Exception as e:
        return {"error": str(e)[:160]}


def _check_fence(_a):
    # 좌표는 'fence 됨'이라는데, 실제로 서울 prod-rds 의 SG 가 빈 fence-sg 로 바뀌었는지 실물 확인
    try:
        d = boto3.client("rds", region_name=SEOUL).describe_db_instances(
            DBInstanceIdentifier=PROD_RDS_ID)["DBInstances"][0]
        sgs = [g["VpcSecurityGroupId"] for g in d.get("VpcSecurityGroups", [])
               if g.get("Status") == "active"]
        return {"prod_rds_sgs": sgs, "fence_sg_id": FENCE_SG_ID,
                "is_fenced": bool(FENCE_SG_ID) and sgs == [FENCE_SG_ID]}
    except Exception as e:
        return {"error": str(e)[:160], "note": "서울 도달 불가면 fence 실물 확인 불가(좌표 신호로 판단)"}


def _check_s3_replication(_a):
    # CRR 지연. 단 이 계정은 복제 규칙에 metrics{} 가 꺼져 있어 ReplicationLatency 가 발행되지 않는다 →
    # best-effort: 기본 일일 지표 NumberOfObjects 로 source(서울)↔dest(도쿄) 객체 수를 대략 비교하고, 공백을 지적.
    def _obj_count(bucket, region):
        try:
            cw = boto3.client("cloudwatch", region_name=region)
            m = cw.get_metric_statistics(
                Namespace="AWS/S3", MetricName="NumberOfObjects",
                Dimensions=[{"Name": "BucketName", "Value": bucket},
                            {"Name": "StorageType", "Value": "AllStorageTypes"}],
                StartTime=datetime.datetime.utcnow() - datetime.timedelta(days=3),
                EndTime=datetime.datetime.utcnow(), Period=86400, Statistics=["Average"])
            pts = sorted(m.get("Datapoints", []), key=lambda p: p["Timestamp"])
            return int(pts[-1]["Average"]) if pts else None
        except Exception:
            return None
    src, dst = _obj_count(S3_SRC, SEOUL), _obj_count(S3_DST, REGION)
    return {"metrics_enabled": False, "source_objects": src, "dest_objects": dst,
            "objects_behind": (src - dst) if (src is not None and dst is not None) else None,
            "note": "S3 복제 규칙에 metrics{} 미활성 → ReplicationLatency 정밀 측정 불가. "
                    "NumberOfObjects(일 단위) 근사. 권고: prod images_crr 규칙에 metrics 활성화."}


TOOLS = {
    "reprobe_seoul": _reprobe_seoul, "describe_rds": _describe_rds, "get_coordinator": _get_coordinator,
    "run_db_check": _run_db_check, "check_fence": _check_fence, "check_s3_replication": _check_s3_replication,
}

TOOL_SPEC = [
    {"toolSpec": {"name": "reprobe_seoul",
        "description": "서울 ALB /health 를 직접 다시 호출해 서울이 정말 죽었는지 독립 재확인한다(살아있으면 분열 위험).",
        "inputSchema": {"json": {"type": "object", "properties": {}}}}},
    {"toolSpec": {"name": "describe_rds",
        "description": "RDS 상태 조회. which='dr'=도쿄 dr-rds(승격됐나), which='prod'=서울 prod-rds(아직 살아있나).",
        "inputSchema": {"json": {"type": "object",
            "properties": {"which": {"type": "string", "enum": ["dr", "prod"]}}, "required": ["which"]}}}},
    {"toolSpec": {"name": "get_coordinator",
        "description": "좌표(DynamoDB)의 단일 writer 상태 — 주인이 도쿄인지, fence 끝났는지, 서울이 살아있는지.",
        "inputSchema": {"json": {"type": "object", "properties": {}}}}},
    {"toolSpec": {"name": "run_db_check",
        "description": "승격된 도쿄 DB에 읽기전용 정합성 쿼리를 돌린다. check 중 하나를 골라라: "
                       "seq_gap(시퀀스 vs max id, table 필요), recency(최신 쓰기 시각, table), "
                       "orphans(고아 레코드, table=관계명), rowcount(추정 행수, table), "
                       "connections(앱 접속 수, table 불필요), billing(결제·구독 불변식, table 불필요).",
        "inputSchema": {"json": {"type": "object",
            "properties": {"check": {"type": "string",
                "enum": ["seq_gap", "recency", "orphans", "rowcount", "connections", "billing"]},
                "table": {"type": "string",
                "enum": ["users", "farm_diaries", "subscriptions", "payments", "content_jobs"]}},
            "required": ["check"]}}}},
    {"toolSpec": {"name": "check_fence",
        "description": "서울 prod-rds 의 보안그룹이 실제로 빈 fence-sg 로 바뀌었는지 확인한다(좌표 말고 실물 차단 확인).",
        "inputSchema": {"json": {"type": "object", "properties": {}}}}},
    {"toolSpec": {"name": "check_s3_replication",
        "description": "DR S3 복제가 따라잡았는지(이미지·콘텐츠 완전성)를 best-effort 로 본다.",
        "inputSchema": {"json": {"type": "object", "properties": {}}}}},
]


# ── 좌표 파싱 + 결정론 판정(분기는 AI 아님) ───────────────────
def _coord(item):
    return {"current_primary": item.get("current_primary", {}).get("S"),
            "fence_pending": item.get("fence_pending", {}).get("BOOL", True),
            "seoul_health_ok": item.get("seoul_health", {}).get("BOOL", True)}


def _rule(base, coord):
    # danger=즉시대응 / suspect=사람확인 / ok=정상. seq_ok(시퀀스 정합)도 게이트에 반영.
    if not base.get("writable") or base.get("in_recovery") or coord.get("current_primary") != "tokyo":
        return "danger"
    if coord.get("fence_pending") or coord.get("seoul_health_ok") or base.get("seq_ok") is False:
        return "suspect"
    return "ok"


def _read_coordinator():
    try:
        return _coord(boto3.client("dynamodb", region_name=REGION).get_item(
            TableName=TABLE, Key={"key": {"S": "primary"}}).get("Item", {}))
    except Exception:
        return {"current_primary": None, "fence_pending": True, "seoul_health_ok": True}


# ── 에이전트 루프 ─────────────────────────────────────────────
def handler(event, _ctx):
    base = event.get("verify", event)
    coord = _read_coordinator()
    verdict = _rule(base, coord)                                    # 분기는 여기서 결정론적으로 확정

    user = ("promote 직후 검수다. baseline 신호와 좌표는 아래와 같다. 필요하면 도구로 더 조사한 뒤 판정해라.\n"
            f"- baseline: {json.dumps(base, ensure_ascii=False)}\n"
            f"- coordinator: {json.dumps(coord, ensure_ascii=False)}\n"
            f"- 결정론 Rule 1차 판정(참고): {verdict}")
    messages = [{"role": "user", "content": [{"text": user}]}]
    br = boto3.client("bedrock-runtime", region_name=REGION)
    tools_used = []

    try:
        for _ in range(MAX_TURNS):
            r = br.converse(modelId=MODEL_ID, system=[{"text": SYSTEM}], messages=messages,
                            toolConfig={"tools": TOOL_SPEC},
                            inferenceConfig={"maxTokens": 1500, "temperature": 0.2})
            out = r["output"]["message"]
            messages.append(out)
            if r.get("stopReason") != "tool_use":
                break
            results = []
            for blk in out["content"]:
                if "toolUse" not in blk:
                    continue
                tu = blk["toolUse"]
                tools_used.append(tu["name"])
                res = TOOLS.get(tu["name"], lambda a: {"error": "unknown tool"})(tu.get("input") or {})
                results.append({"toolResult": {"toolUseId": tu["toolUseId"], "content": [{"json": res}]}})
            messages.append({"role": "user", "content": results})

        text = "".join(b.get("text", "") for b in messages[-1]["content"])
        return {"audit_ko": text, "rule_verdict": verdict,
                "tools_used": tools_used, "ai_unavailable": False}
    except Exception as e:
        return {"audit_ko": f"(AI 검수 불가: {e}) 신호 원본으로 사람이 판단할 것.",
                "rule_verdict": verdict, "tools_used": tools_used, "ai_unavailable": True}
