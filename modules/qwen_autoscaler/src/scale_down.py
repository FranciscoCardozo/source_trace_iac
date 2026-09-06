"""Apaga el servicio qwen-inference cuando el pipeline esta inactivo.

Lo dispara EventBridge cada pocos minutos. Reglas:
  - si hay alguna ejecucion del Step Functions en RUNNING -> no toca nada
  - si la ultima ejecucion termino hace menos de IDLE_MINUTES -> deja el
    modelo prendido (evita thrash entre jobs seguidos)
  - si no -> desiredCount = 0

El scale-up lo hace el propio Step Functions (estado EnsureModelUp), asi que
si un job arranca justo despues del scale-down, se vuelve a prender solo.
"""

import os
from datetime import datetime, timedelta, timezone

import boto3

sfn = boto3.client("stepfunctions")
ecs = boto3.client("ecs")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
ECS_CLUSTER = os.environ["ECS_CLUSTER"]
MODEL_SERVICE = os.environ["MODEL_SERVICE"]
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES", "10"))


def handler(event, context):
    running = sfn.list_executions(
        stateMachineArn=STATE_MACHINE_ARN, statusFilter="RUNNING", maxResults=1
    )["executions"]
    if running:
        print("hay ejecuciones RUNNING, se mantiene el modelo prendido")
        return {"action": "keep", "reason": "running_executions"}

    recent = sfn.list_executions(stateMachineArn=STATE_MACHINE_ARN, maxResults=1)["executions"]
    if recent:
        stopped = recent[0].get("stopDate")
        if stopped and stopped > datetime.now(timezone.utc) - timedelta(minutes=IDLE_MINUTES):
            print(f"ultima ejecucion termino {stopped.isoformat()}, dentro del grace period")
            return {"action": "keep", "reason": "within_grace_period"}

    svc = ecs.describe_services(cluster=ECS_CLUSTER, services=[MODEL_SERVICE])["services"][0]
    if svc["desiredCount"] == 0:
        print("ya esta en 0")
        return {"action": "noop", "reason": "already_zero"}

    ecs.update_service(cluster=ECS_CLUSTER, service=MODEL_SERVICE, desiredCount=0)
    print("scaled qwen-inference a desiredCount=0")
    return {"action": "scaled_down"}
