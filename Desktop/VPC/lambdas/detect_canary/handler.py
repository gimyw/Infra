# lambdas/detect_canary/handler.py  —  도쿄에서 서울을 밖에서 확인 + 장애 시 failover 자동 시작
# 표준 라이브러리 + boto3(런타임 기본 제공)만 쓴다 — 의존성 zip 불필요, VPC 불필요.
import os, json, ssl, datetime, urllib.request, boto3

REGION     = "ap-northeast-1"
HEALTH_URL = os.environ["SEOUL_HEALTH_URL"]    # 서울 ALB '직접' 주소 (failover 도메인 아님!)
TABLE      = os.environ["COORDINATOR_TABLE"]   # dr-brain-coordinator
ALERT      = os.environ["ALERT_TOPIC"]         # dr-brain-approvals SNS
HC_ID      = os.environ.get("ROUTE53_HC_ID", "")
SM_ARN     = os.environ.get("STATE_MACHINE_ARN", "")  # confirmed_down이면 자동 시작할 failover 상태기계


# 서울 ALB를 ELB DNS로 직접 부르면 인증서 CN(api.farmily.info)과 호스트가 안 맞는다.
# 알려진 서울 prod ALB의 /health probe라 검증을 끈다 — GET뿐, 민감정보 전송 없음.
# (이렇게 직접 보면 failover 도메인을 안 거쳐 '서울만' 본다: 응답 body region=ap-northeast-2)
_NOVERIFY = ssl._create_unverified_context()


def _http_ok(url):
    try:
        with urllib.request.urlopen(url, timeout=4, context=_NOVERIFY) as r:
            return r.status == 200
    except Exception:
        return False


def _route53_down():
    # Route53 health check 지표는 us-east-1에만 있다 (D1). 없으면 None(교차검증 생략)
    if not HC_ID:
        return None
    cw = boto3.client("cloudwatch", region_name="us-east-1")
    m = cw.get_metric_statistics(
        Namespace="AWS/Route53", MetricName="HealthCheckStatus",
        Dimensions=[{"Name": "HealthCheckId", "Value": HC_ID}],
        StartTime=datetime.datetime.utcnow() - datetime.timedelta(minutes=2),
        EndTime=datetime.datetime.utcnow(), Period=60, Statistics=["Minimum"])
    pts = m.get("Datapoints", [])
    return bool(pts) and min(p["Minimum"] for p in pts) < 1   # 1 미만 = 비정상


def _running(sf):
    # 이미 진행 중인 failover 실행이 있나 — 1분마다 도는 canary가 중복 시작하지 않도록.
    try:
        ex = sf.list_executions(stateMachineArn=SM_ARN, statusFilter="RUNNING", maxResults=1)["executions"]
        return bool(ex)
    except Exception:
        return False


def handler(event, _ctx):
    health_ok = _http_ok(HEALTH_URL)
    r53_down  = _route53_down()
    confirmed_down = (not health_ok) and (r53_down is not False)   # 둘 다 down(또는 교차검증 불가)

    ddb = boto3.client("dynamodb", region_name=REGION)
    cur = ddb.get_item(TableName=TABLE, Key={"key": {"S": "primary"}}).get("Item", {})
    primary   = (cur.get("current_primary") or {}).get("S", "seoul")
    triggered = (cur.get("failover_triggered") or {}).get("BOOL", False)  # 이 장애 에피소드에서 이미 시작했나
    armed     = (cur.get("armed") or {}).get("BOOL", False)               # 실전 드릴 전 사람이 켜는 플래그(기본 false)

    ddb.update_item(
        TableName=TABLE, Key={"key": {"S": "primary"}},
        UpdateExpression="SET seoul_health = :h, last_probe = :t",
        ExpressionAttributeValues={":h": {"BOOL": health_ok}, ":t": {"S": event.get("time", "")}})

    out = {"seoul_health_ok": health_ok, "route53_down": r53_down,
           "confirmed_down": confirmed_down, "armed": armed, "started": False}

    if confirmed_down:
        boto3.client("sns", region_name=REGION).publish(
            TopicArn=ALERT, Subject="[DR] 서울 장애 감지",
            Message=json.dumps(out, ensure_ascii=False))
        # 자동 시작 — 평시(서울 primary)이고, 이 에피소드에서 아직 안 시작했고, 진행 중 실행이 없을 때만.
        # arm_promote는 coordinator의 armed 플래그를 따른다(기본 false=dry-run → 오탐이 진짜 promote를 못 켠다).
        if SM_ARN and primary == "seoul" and not triggered:
            sf = boto3.client("stepfunctions", region_name=REGION)
            if not _running(sf):
                sf.start_execution(stateMachineArn=SM_ARN, input=json.dumps({"arm_promote": armed}))
                ddb.update_item(
                    TableName=TABLE, Key={"key": {"S": "primary"}},
                    UpdateExpression="SET failover_triggered = :t",
                    ExpressionAttributeValues={":t": {"BOOL": True}})
                out["started"] = True
    elif health_ok and triggered:
        # 서울이 돌아오면 트리거를 리셋한다(다음 장애 에피소드에 다시 시작할 수 있게).
        ddb.update_item(
            TableName=TABLE, Key={"key": {"S": "primary"}},
            UpdateExpression="SET failover_triggered = :f",
            ExpressionAttributeValues={":f": {"BOOL": False}})

    return out
