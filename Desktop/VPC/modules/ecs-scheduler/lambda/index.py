import boto3
import os

ecs = boto3.client("ecs")
aas = boto3.client("application-autoscaling")

def handler(event, context):
    cluster = os.environ["ECS_CLUSTER"]
    service = os.environ["ECS_SERVICE"]
    action = event.get("action")

    resource_id = f"service/{cluster}/{service}"

    if action == "start":
        desired = 1
        max_cap = 2
    elif action == "stop":
        desired = 0
        max_cap = 0
    else:
        raise ValueError(f"Unknown action: {action}")

    aas.register_scalable_target(
        ServiceNamespace="ecs",
        ResourceId=resource_id,
        ScalableDimension="ecs:service:DesiredCount",
        MinCapacity=desired,
        MaxCapacity=max_cap,
    )

    ecs.update_service(cluster=cluster, service=service, desiredCount=desired)
    print(f"Updated {service} min={desired}, max={max_cap}, desiredCount={desired}")
