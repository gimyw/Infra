# lambdas/traffic_pin/handler.py  —  사용자 트래픽을 도쿄에 고정/해제 (수동)
# pin:   서울 ALB health check의 경로를 항상 404나는 경로로 바꿔 강제 unhealthy → Route53 failover가
#        도쿄로만 응답. FIS가 15분 뒤 서울을 살려도 트래픽이 안 되돌아간다(auto-failback 차단). 원래 경로는 백업.
# unpin: 백업한 원래 경로로 되돌려 정상 health 기반 failover 거동 복귀(서울 health 살아나면 서울).
# ⚠️ 자동화 금지 — 실전 failover 중에만 의식적으로. fence(DB 층)의 트래픽 층 짝.
# 표준 라이브러리 + boto3만 — 의존성 zip·VPC 불필요.
import os, boto3

REGION = "ap-northeast-1"          # Route53은 글로벌 — 클라이언트 리전은 도쿄로 통일
TABLE = os.environ["COORDINATOR_TABLE"]
HC_ID = os.environ["HEALTH_CHECK_ID"]
FAIL_PATH = "/__dr_pinned__"       # 항상 404 → health check unhealthy → Route53가 도쿄로


def handler(event, _ctx):
    action = event.get("action", "")
    r53 = boto3.client("route53", region_name=REGION)
    ddb = boto3.client("dynamodb", region_name=REGION)

    if action == "pin":
        cfg = r53.get_health_check(HealthCheckId=HC_ID)["HealthCheck"]["HealthCheckConfig"]
        orig = cfg.get("ResourcePath", "/")
        if orig != FAIL_PATH:                          # 원래 경로 백업(unpin 복구용)
            ddb.update_item(
                TableName=TABLE, Key={"key": {"S": "primary"}},
                UpdateExpression="SET r53_prev_path = :o, traffic_pinned = :t",
                ExpressionAttributeValues={":o": {"S": orig}, ":t": {"BOOL": True}})
        r53.update_health_check(HealthCheckId=HC_ID, ResourcePath=FAIL_PATH)
        return {"ok": True, "action": "pin", "fail_path": FAIL_PATH}

    if action == "unpin":
        item = ddb.get_item(TableName=TABLE, Key={"key": {"S": "primary"}}).get("Item", {})
        orig = (item.get("r53_prev_path") or {}).get("S", "/api/v1/health")
        r53.update_health_check(HealthCheckId=HC_ID, ResourcePath=orig)
        ddb.update_item(
            TableName=TABLE, Key={"key": {"S": "primary"}},
            UpdateExpression="SET traffic_pinned = :f REMOVE r53_prev_path",
            ExpressionAttributeValues={":f": {"BOOL": False}})
        return {"ok": True, "action": "unpin", "restored_path": orig}

    return {"ok": False, "reason": "action은 pin 또는 unpin"}
