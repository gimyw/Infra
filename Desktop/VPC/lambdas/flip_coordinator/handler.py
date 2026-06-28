# lambdas/flip_coordinator/handler.py  —  좌표를 도쿄로 넘긴다
# "이제 주 DB는 도쿄"라고 좌표에 기록(여전히 epoch 소유 확인)하고, 앱이 읽을 promoted 시크릿에
# 새 쓰기 엔드포인트를 써넣는다. Route53은 안 건드린다 — 트래픽은 이미 자동 failover로 도쿄에 와 있다(D2).
import os, json, boto3

REGION = "ap-northeast-1"
TABLE, PROMOTED_SECRET = os.environ["COORDINATOR_TABLE"], os.environ["PROMOTED_SECRET"]


def handler(event, _ctx):
    endpoint = event["promote"].get("endpoint")        # describe로 얻은 새 primary 주소
    epoch    = event["fence"]["epoch"]

    boto3.client("dynamodb", region_name=REGION).update_item(
        TableName=TABLE, Key={"key": {"S": "primary"}},
        UpdateExpression="SET current_primary = :t, promoted_endpoint = :e, fencing_in_progress = :f",
        ConditionExpression="epoch = :ep",             # 내가 아직 이 세대의 주인일 때만
        ExpressionAttributeValues={":t": {"S": "tokyo"}, ":e": {"S": endpoint or ""},
                                   ":f": {"BOOL": False}, ":ep": {"N": str(epoch)}})

    boto3.client("secretsmanager", region_name=REGION).put_secret_value(
        SecretId=PROMOTED_SECRET, SecretString=json.dumps({"DB_HOST": endpoint, "DB_PORT": "5432"}))

    # TODO(후속): farmily-dr 파드 롤아웃 재시작으로 읽기전용 모드를 해제한다.
    # 이 레포엔 아직 SSM/EKS 롤아웃 자동화가 없어(greenfield) 지금은 좌표+시크릿 갱신까지만 한다.
    # 실제 운영 전환 땐 EKS API(rollout restart) 또는 SSM RunCommand로 이 자리를 채운다.
    print("TODO: restart farmily-dr pods to leave read-only mode (no automation wired yet)")

    return {"flipped": True, "pods_restarted": False}
