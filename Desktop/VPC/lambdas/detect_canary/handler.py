# lambdas/detect_canary/handler.py  —  도쿄에서 서울을 밖에서 확인
# 표준 라이브러리 + boto3(런타임 기본 제공)만 쓴다 — 의존성 zip 불필요, VPC 불필요.
import os, json, ssl, datetime, urllib.request, boto3

REGION     = "ap-northeast-1"
HEALTH_URL = os.environ["SEOUL_HEALTH_URL"]    # 서울 ALB '직접' 주소 (failover 도메인 아님!)
TABLE      = os.environ["COORDINATOR_TABLE"]   # dr-brain-coordinator
ALERT      = os.environ["ALERT_TOPIC"]         # dr-brain-approvals SNS
HC_ID      = os.environ.get("ROUTE53_HC_ID", "")


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


def handler(event, _ctx):
    health_ok = _http_ok(HEALTH_URL)
    r53_down  = _route53_down()
    confirmed_down = (not health_ok) and (r53_down is not False)   # 둘 다 down(또는 교차검증 불가)

    boto3.client("dynamodb", region_name=REGION).update_item(
        TableName=TABLE, Key={"key": {"S": "primary"}},
        UpdateExpression="SET seoul_health = :h, last_probe = :t",
        ExpressionAttributeValues={":h": {"BOOL": health_ok}, ":t": {"S": event.get("time", "")}})

    out = {"seoul_health_ok": health_ok, "route53_down": r53_down, "confirmed_down": confirmed_down}
    if confirmed_down:
        boto3.client("sns", region_name=REGION).publish(
            TopicArn=ALERT, Subject="[DR] 서울 장애 감지",
            Message=json.dumps(out, ensure_ascii=False))
    return out
