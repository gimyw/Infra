# lambdas/audit_agent/handler.py  —  Failover 검수 에이전트 (Bedrock Converse tool-use 루프)
#
# promote 직후, split-brain/정합성을 '스스로 조사'하는 읽기전용 에이전트다.
# 단발 호출이 아니라 도구를 골라가며 도는 루프라서 워크플로우가 아니라 '에이전트'다.
#   - 도구는 전부 읽기전용(서울 재-probe·RDS describe·좌표 읽기). 행동(promote·fence) 절대 안 함.
#   - 분기(rule_verdict)는 AI가 아니라 결정론적 _rule()이 정한다(AI가 죽어도 분기는 안 흔들림).
#   - AI는 그 위에 '왜 그런지·무엇을 더 봐야 하는지'를 한국어로 조사·설명·권고만 한다.
# 표준 라이브러리 + boto3(런타임 기본)만 — 의존성 zip·VPC 불필요(Bedrock·DynamoDB·RDS API·공개 health만).
import os, json, ssl, urllib.request, boto3

REGION, SEOUL = "ap-northeast-1", "ap-northeast-2"
MODEL_ID    = os.environ["MODEL_ID"]
TABLE       = os.environ["COORDINATOR_TABLE"]
HEALTH_URL  = os.environ["SEOUL_HEALTH_URL"]
DR_RDS_ID   = os.environ.get("DR_RDS_ID", "dr-rds")
PROD_RDS_ID = os.environ.get("PROD_RDS_ID", "prod-rds")
MAX_TURNS   = 5                                    # 도구 루프 상한(비용·시간 가드)

SYSTEM = (
    "너는 DR failover 검수관이다. promote 직후 새 주 DB(도쿄)가 split-brain 없이 제대로 섰는지 조사한다. "
    "주어진 baseline 신호로 출발해, 필요하면 읽기전용 도구로 직접 더 확인한 뒤 판정한다. "
    "절대 어떤 것도 실행·변경하지 않는다(읽기만). 확실치 않으면 보수적으로(의심) 본다. "
    "도구로 충분히 확인했으면 한국어로 ① 종합 판정(안전/의심/분열 징후 중 하나) ② 근거(어떤 신호가 정상/이상) "
    "③ 운영자 권고 액션을 쓴다. '도쿄가 유일한 writer'여야 안전하다 — 서울이 아직 살아 서빙하거나 fence가 "
    "안 끝났으면 분열 위험이다."
)

# ── 읽기전용 도구 3개 ─────────────────────────────────────────
_NOVERIFY = ssl._create_unverified_context()       # ELB DNS 직접 probe(인증서 CN 불일치 회피)


def _reprobe_seoul(_args):
    # 서울 ALB /health를 다시 직접 친다 — 정말 죽었는지 독립 재확인(살아있으면 분열 위험)
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=4, context=_NOVERIFY) as r:
            return {"seoul_health_ok": r.status == 200, "status": r.status}
    except Exception as e:
        return {"seoul_health_ok": False, "error": str(e)[:120]}


def _describe_rds(args):
    # dr-rds(도쿄) / prod-rds(서울) 상태. 도쿄가 standalone primary 됐는지 + 서울이 아직 available인지.
    which = (args or {}).get("which", "dr")
    ident, region = (DR_RDS_ID, REGION) if which == "dr" else (PROD_RDS_ID, SEOUL)
    try:
        d = boto3.client("rds", region_name=region).describe_db_instances(
            DBInstanceIdentifier=ident)["DBInstances"][0]
        return {
            "identifier": ident, "region": region,
            "status": d.get("DBInstanceStatus"),
            "is_read_replica": bool(d.get("ReadReplicaSourceDBInstanceIdentifier")),
            "source": d.get("ReadReplicaSourceDBInstanceIdentifier"),
        }
    except Exception as e:
        return {"identifier": ident, "region": region, "error": str(e)[:120]}


def _get_coordinator(_args):
    try:
        item = boto3.client("dynamodb", region_name=REGION).get_item(
            TableName=TABLE, Key={"key": {"S": "primary"}}).get("Item", {})
        return _coord(item)
    except Exception as e:
        return {"error": str(e)[:120]}


TOOLS = {
    "reprobe_seoul":   _reprobe_seoul,
    "describe_rds":    _describe_rds,
    "get_coordinator": _get_coordinator,
}

TOOL_SPEC = [
    {"toolSpec": {
        "name": "reprobe_seoul",
        "description": "서울 ALB /health를 직접 다시 호출해 서울이 정말 죽었는지 독립 재확인한다. 살아있으면 분열 위험.",
        "inputSchema": {"json": {"type": "object", "properties": {}}}}},
    {"toolSpec": {
        "name": "describe_rds",
        "description": "RDS 인스턴스 상태 조회. which='dr'면 도쿄 dr-rds(승격됐는지), which='prod'면 서울 prod-rds(아직 살아있는지).",
        "inputSchema": {"json": {"type": "object",
            "properties": {"which": {"type": "string", "enum": ["dr", "prod"]}},
            "required": ["which"]}}}},
    {"toolSpec": {
        "name": "get_coordinator",
        "description": "좌표(DynamoDB)에서 현재 단일 writer 상태를 읽는다 — 주인이 도쿄인지, fence가 끝났는지, 서울이 살아있는지.",
        "inputSchema": {"json": {"type": "object", "properties": {}}}}},
]


# ── 좌표 파싱 + 결정론 판정(분기는 AI 아님) ───────────────────
def _coord(item):
    return {
        "current_primary": item.get("current_primary", {}).get("S"),
        "fence_pending": item.get("fence_pending", {}).get("BOOL", True),
        "seoul_health_ok": item.get("seoul_health", {}).get("BOOL", True),
    }


def _rule(base, coord):
    # danger=즉시대응 / suspect=사람확인 / ok=정상. dr-7 가이드 로직.
    if not base.get("writable") or base.get("in_recovery") or coord.get("current_primary") != "tokyo":
        return "danger"
    if coord.get("fence_pending") or coord.get("seoul_health_ok"):
        return "suspect"
    return "ok"


def _read_coordinator():
    try:
        item = boto3.client("dynamodb", region_name=REGION).get_item(
            TableName=TABLE, Key={"key": {"S": "primary"}}).get("Item", {})
        return _coord(item)
    except Exception:
        return {"current_primary": None, "fence_pending": True, "seoul_health_ok": True}


# ── 에이전트 루프 ─────────────────────────────────────────────
def handler(event, _ctx):
    base = event.get("verify", event)                    # Verify 단계의 baseline 신호
    coord = _read_coordinator()
    verdict = _rule(base, coord)                          # 분기는 여기서 결정론적으로 확정

    user = (
        "promote 직후 검수다. baseline 신호와 좌표는 아래와 같다. "
        "필요하면 도구로 더 조사한 뒤 판정해라.\n"
        f"- baseline: {json.dumps(base, ensure_ascii=False)}\n"
        f"- coordinator: {json.dumps(coord, ensure_ascii=False)}\n"
        f"- 결정론 Rule 1차 판정(참고): {verdict}"
    )
    messages = [{"role": "user", "content": [{"text": user}]}]
    br = boto3.client("bedrock-runtime", region_name=REGION)
    tools_used = []

    try:
        for _ in range(MAX_TURNS):
            r = br.converse(
                modelId=MODEL_ID, system=[{"text": SYSTEM}],
                messages=messages, toolConfig={"tools": TOOL_SPEC},
                inferenceConfig={"maxTokens": 1200, "temperature": 0.2})
            out = r["output"]["message"]
            messages.append(out)
            if r.get("stopReason") != "tool_use":
                break
            results = []
            for blk in out["content"]:                   # 모델이 요청한 도구들 실행
                if "toolUse" not in blk:
                    continue
                tu = blk["toolUse"]
                tools_used.append(tu["name"])
                res = TOOLS.get(tu["name"], lambda a: {"error": "unknown tool"})(tu.get("input") or {})
                results.append({"toolResult": {
                    "toolUseId": tu["toolUseId"],
                    "content": [{"json": res}]}})
            messages.append({"role": "user", "content": results})

        text = "".join(b.get("text", "") for b in messages[-1]["content"])
        return {"audit_ko": text, "rule_verdict": verdict,
                "tools_used": tools_used, "ai_unavailable": False}
    except Exception as e:                                # AI가 죽어도 분기는 살아 있다
        return {"audit_ko": f"(AI 검수 불가: {e}) 신호 원본으로 사람이 판단할 것.",
                "rule_verdict": verdict, "tools_used": tools_used, "ai_unavailable": True}
