# lambdas/unfence/handler.py  —  fence 되돌리기 (수동 복구 도구)
# coordinator에 fence가 백업해 둔 prev_sgs로 prod-rds의 SG를 원복한다.
# ⚠️ 자동화 금지 — 실전 promote 후 서울을 되살리면 split-brain. "이건 드릴이었다"고 사람이 결정할 때만 호출.
# 표준 라이브러리 + boto3만 — 의존성 zip·VPC 불필요.
import os, boto3

TOKYO, SEOUL = "ap-northeast-1", "ap-northeast-2"
TABLE, PROD_RDS = os.environ["COORDINATOR_TABLE"], os.environ["PROD_RDS_ID"]


def handler(event, _ctx):
    ddb = boto3.client("dynamodb", region_name=TOKYO)
    item = ddb.get_item(TableName=TABLE, Key={"key": {"S": "primary"}}).get("Item", {})
    prev = (item.get("prev_sgs") or {}).get("S", "")
    sgs = [s for s in prev.split(",") if s]
    if not sgs:
        return {"unfenced": False, "reason": "백업된 prev_sgs 없음 — fence가 실행된 적 없거나 이미 복구됨"}

    boto3.client("rds", region_name=SEOUL).modify_db_instance(
        DBInstanceIdentifier=PROD_RDS, VpcSecurityGroupIds=sgs, ApplyImmediately=True)

    # 복구 표식 정리 + 백업 제거(다음 fence가 새로 백업하도록)
    ddb.update_item(
        TableName=TABLE, Key={"key": {"S": "primary"}},
        UpdateExpression="SET fencing_in_progress = :f, fence_pending = :f REMOVE prev_sgs",
        ExpressionAttributeValues={":f": {"BOOL": False}})
    return {"unfenced": True, "restored_sgs": sgs}
