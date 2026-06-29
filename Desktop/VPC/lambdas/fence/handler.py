# lambdas/fence/handler.py  —  구 서울을 막는다 (비가역 체인의 첫 단계)
# epoch CAS로 동시 실행을 잠그고, 서울에 닿으면 prod-rds의 SG를 빈 fence-sg로 통째 교체한다.
# 못 닿으면 fence_pending=true로 표시했다가 서울 복귀 시 다시 막는다(D4 best-effort + deferred fence).
# arm_promote=false면 아무것도 안 하고 dry-run 반환(게임데이 안전핀, D6).
import os, boto3, botocore

TOKYO, SEOUL = "ap-northeast-1", "ap-northeast-2"
TABLE = os.environ["COORDINATOR_TABLE"]
FENCE_SG, PROD_RDS = os.environ["FENCE_SG_ID"], os.environ["PROD_RDS_ID"]
SEOUL_SECRET = os.environ.get("SEOUL_DB_SECRET", "")   # 비번 로테이션은 선택(공유 시크릿이면 비워둠)


def _bump_epoch():                                     # 동시 promote를 막는 잠금(CAS)
    ddb = boto3.client("dynamodb", region_name=TOKYO)
    cur = ddb.get_item(TableName=TABLE, Key={"key": {"S": "primary"}})["Item"]
    e = int(cur["epoch"]["N"])
    ddb.update_item(
        TableName=TABLE, Key={"key": {"S": "primary"}},
        UpdateExpression="SET epoch = :n, fencing_in_progress = :t",
        ConditionExpression="epoch = :e AND fencing_in_progress = :f",
        ExpressionAttributeValues={":n": {"N": str(e + 1)}, ":e": {"N": str(e)},
                                   ":t": {"BOOL": True}, ":f": {"BOOL": False}})
    return e + 1


def handler(event, _ctx):
    if not event.get("arm_promote", False):
        return {"fenced": False, "dry_run": True}      # 드릴: 로그만 남기고 끝

    try:
        epoch = _bump_epoch()
    except botocore.exceptions.ClientError:            # 다른 실행이 이미 전진 = 중단
        return {"aborted": True, "reason": "epoch advanced — 동시 실행 감지"}

    pending, steps = False, {}
    try:                                               # 서울에 닿을 때만 (D4)
        rds = boto3.client("rds", region_name=SEOUL)
        # 교체 전 현재 SG를 백업한다(unfence 복구용). 이미 fence-sg뿐이면 진짜 백업을 덮어쓰지 않는다.
        cur = [g["VpcSecurityGroupId"]
               for g in rds.describe_db_instances(DBInstanceIdentifier=PROD_RDS)["DBInstances"][0]["VpcSecurityGroups"]
               if g.get("Status") != "removing"]
        if cur and cur != [FENCE_SG]:
            boto3.client("dynamodb", region_name=TOKYO).update_item(
                TableName=TABLE, Key={"key": {"S": "primary"}},
                UpdateExpression="SET prev_sgs = :s",
                ExpressionAttributeValues={":s": {"S": ",".join(cur)}})
            steps["prev_sgs"] = ",".join(cur)          # unfence가 이 값으로 원복
        rds.modify_db_instance(
            DBInstanceIdentifier=PROD_RDS, VpcSecurityGroupIds=[FENCE_SG], ApplyImmediately=True)
        steps["sg"] = "swapped"                         # SG 리스트를 원자적으로 교체(인라인 편집 X)
        if SEOUL_SECRET:
            boto3.client("secretsmanager", region_name=SEOUL).rotate_secret(SecretId=SEOUL_SECRET)
            steps["secret"] = "rotated"
    except Exception as e:
        steps["error"], pending = str(e), True         # 못 닿음 → 복귀 시 재시도

    boto3.client("dynamodb", region_name=TOKYO).update_item(
        TableName=TABLE, Key={"key": {"S": "primary"}},
        UpdateExpression="SET fence_pending = :p", ExpressionAttributeValues={":p": {"BOOL": pending}})
    return {"fenced": not pending, "epoch": epoch, "fence_pending": pending, "steps": steps}
