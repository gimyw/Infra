import boto3
import os

ecs = boto3.client("ecs")

def handler(event, context):
    cluster = os.environ["ECS_CLUSTER"]
    service = os.environ["ECS_SERVICE"]
    action = event.get("action")

    if action == "start":
        desired = 1
    elif action == "stop":
        desired = 0
    else:
        raise ValueError(f"Unknown action: {action}")

    ecs.update_service(cluster=cluster, service=service, desiredCount=desired)
    print(f"Updated {service} desiredCount to {desired}")
