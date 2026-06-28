# lambdas/promote/handler.py  —  도쿄 replica를 주 DB로 승격한다 (되돌릴 수 없음)
# arm_promote=true일 때만 promote를 '시작'만 한다. 완료(available) 대기는 Step Functions가 폴링한다
# (promote는 수 분 걸려 Lambda 15분 한도를 넘길 수 있으므로 여기서 기다리지 않는다).
import os, boto3

REGION, DR_RDS = "ap-northeast-1", os.environ["DR_RDS_ID"]


def handler(event, _ctx):
    if not event.get("arm_promote", False):
        return {"promoted": False, "dry_run": True}
    boto3.client("rds", region_name=REGION).promote_read_replica(DBInstanceIdentifier=DR_RDS)
    return {"promote_started": True}                   # 완료 대기는 Step Functions(WaitPromote 루프)
