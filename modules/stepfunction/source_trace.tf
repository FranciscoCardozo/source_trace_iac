# ------------------------------------------------------------------
# AWS Step Functions workflow - orquestacion del analisis
#
#   invoker Lambda -> StartExecution  (input: { jobId, payload })
#     MarkRunning            (DynamoDB: status = RUNNING)
#     getSource              (ecs:runTask.sync, jobType=getSource)
#     basicAnalysis          (ecs:runTask.sync, jobType=basicAnalysis)
#     functionalResume       (ecs:runTask.sync, jobType=functionalResume)
#     componentAnalysis      (ecs:runTask.sync, jobType=componentAnalysis)
#     arquitectureAnalysis   (ecs:runTask.sync, jobType=arquitectureAnalysis)
#     MarkSucceeded / MarkFailed  (DynamoDB: status final)
#
# Cada paso es una task Fargate efimera de la misma familia de task
# definition; el Step Functions le pasa el nombre del paso como override
# de entorno (jobType) y espera (.sync) a que la task pare con exit code 0.
# El estado compartido entre pasos vive en repo-efs (/mnt/repo/<jobId>).
# No hay SQS: el contenedor no hace polling ni callbacks.
#
# Contrato de entrada: la Lambda invoker hace StartExecution con
#   { "jobId": "<id>", "payload": { ... } }
# payload se serializa y se pasa al contenedor como env PAYLOAD (string JSON).
# ------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  state_machine_name = "${var.name}_analysis"

  first_step = var.pipeline_steps[0]

  # Un estado ecs:runTask.sync por paso, encadenados; el ultimo va a MarkSucceeded.
  # El nombre del paso es tambien el nombre del estado.
  step_states = {
    for i, step in var.pipeline_steps : step => {
      Type     = "Task"
      Resource = "arn:aws:states:::ecs:runTask.sync"
      Parameters = {
        LaunchType     = "FARGATE"
        Cluster        = var.ecs_cluster_arn
        TaskDefinition = var.ecs_task_definition_family
        NetworkConfiguration = {
          AwsvpcConfiguration = {
            Subnets        = var.private_subnet_ids
            SecurityGroups = [var.security_group_id]
            AssignPublicIp = "DISABLED"
          }
        }
        Overrides = {
          ContainerOverrides = [{
            Name = var.ecs_container_name
            # El contenedor lee env vars discretas en SCREAMING_SNAKE_CASE.
            # JOB_TYPE elige la implementacion del paso (factory: getSource /
            # basicAnalysis / ...). SOURCE_* salen del payload del request.
            Environment = [
              { Name = "JOB_TYPE", Value = step },
              { Name = "JOB_ID", "Value.$" = "$.jobId" },
              { Name = "SOURCE_TYPE", "Value.$" = "$.payload.sourceType" },
              { Name = "SOURCE_URL", "Value.$" = "$.payload.repoUrl" },
              { Name = "DYNAMODB_TABLE", Value = var.dynamodb_table_name },
              { Name = "PAYLOAD", "Value.$" = "States.JsonToString($.payload)" }
            ]
          }]
        }
      }
      TimeoutSeconds = var.step_timeout_seconds
      Retry = [
        {
          # Errores transitorios del plano de control de ECS (throttling, capacidad).
          ErrorEquals     = ["ECS.AmazonECSException", "ECS.ServerException"]
          IntervalSeconds = 15
          MaxAttempts     = 3
          BackoffRate     = 2.0
        },
        {
          # La task del paso salio con exit code != 0.
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 30
          MaxAttempts     = var.max_retries
          BackoffRate     = 2.0
        }
      ]
      Catch = [
        {
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "MarkFailed"
        }
      ]
      # @@NULL@@ se reemplaza por un null literal despues del jsonencode:
      # descarta la descripcion de la task (enorme) y deja pasar el input intacto.
      ResultPath = "@@NULL@@"
      Next       = i + 1 < length(var.pipeline_steps) ? var.pipeline_steps[i + 1] : "MarkSucceeded"
    }
  }

  states = merge(local.step_states, {
    MarkRunning = {
      Type     = "Task"
      Resource = "arn:aws:states:::dynamodb:updateItem"
      Parameters = {
        TableName = var.dynamodb_table_name
        Key = {
          "PK.$" = "States.Format('JOB#{}', $.jobId)"
          SK     = { S = "META" }
        }
        UpdateExpression         = "SET #s = :s, startedAt = :t, createdAt = if_not_exists(createdAt, :t)"
        ExpressionAttributeNames = { "#s" = "status" }
        ExpressionAttributeValues = {
          ":s" = { S = "RUNNING" }
          ":t" = { "S.$" = "$$.State.EnteredTime" }
        }
      }
      ResultPath = "@@NULL@@"
      Next       = "EnsureModelUp"
    }

    # --- Prende el servidor de inferencia y espera a que este servible ---
    EnsureModelUp = {
      Type     = "Task"
      Resource = "arn:aws:states:::aws-sdk:ecs:updateService"
      Parameters = {
        Cluster      = var.ecs_cluster_arn
        Service      = var.model_service_name
        DesiredCount = 1
      }
      ResultPath = "@@NULL@@"
      Retry = [
        {
          ErrorEquals     = ["States.ALL"]
          IntervalSeconds = 10
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }
      ]
      Next = "WaitForModel"
    }

    WaitForModel = {
      Type    = "Wait"
      Seconds = 15
      Next    = "CheckModel"
    }

    CheckModel = {
      Type     = "Task"
      Resource = "arn:aws:states:::aws-sdk:ecs:describeServices"
      Parameters = {
        Cluster  = var.ecs_cluster_arn
        Services = [var.model_service_name]
      }
      ResultSelector = {
        "runningCount.$" = "$.Services[0].RunningCount"
      }
      ResultPath = "$.model"
      Next       = "ModelReady"
    }

    ModelReady = {
      Type = "Choice"
      Choices = [
        {
          Variable                 = "$.model.runningCount"
          NumericGreaterThanEquals = 1
          Next                     = "ModelWarmup"
        }
      ]
      Default = "WaitForModel"
    }

    ModelWarmup = {
      Type    = "Wait"
      Seconds = var.model_warmup_seconds
      Next    = local.first_step
    }

    MarkSucceeded = {
      Type     = "Task"
      Resource = "arn:aws:states:::dynamodb:updateItem"
      Parameters = {
        TableName = var.dynamodb_table_name
        Key = {
          "PK.$" = "States.Format('JOB#{}', $.jobId)"
          SK     = { S = "META" }
        }
        UpdateExpression         = "SET #s = :s, finishedAt = :t"
        ExpressionAttributeNames = { "#s" = "status" }
        ExpressionAttributeValues = {
          ":s" = { S = "SUCCEEDED" }
          ":t" = { "S.$" = "$$.State.EnteredTime" }
        }
      }
      End = true
    }

    MarkFailed = {
      Type     = "Task"
      Resource = "arn:aws:states:::dynamodb:updateItem"
      Parameters = {
        TableName = var.dynamodb_table_name
        Key = {
          "PK.$" = "States.Format('JOB#{}', $.jobId)"
          SK     = { S = "META" }
        }
        UpdateExpression         = "SET #s = :s, finishedAt = :t, #e = :e"
        ExpressionAttributeNames = { "#s" = "status", "#e" = "error" }
        ExpressionAttributeValues = {
          ":s" = { S = "FAILED" }
          ":t" = { "S.$" = "$$.State.EnteredTime" }
          ":e" = { "S.$" = "States.JsonToString($.error)" }
        }
      }
      Next = "FailState"
    }

    FailState = {
      Type  = "Fail"
      Error = "AnalysisFailed"
      Cause = "Un paso del pipeline reporto un error o excedio el timeout"
    }
  })
}

# --- Log group -------------------------------------------------
resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${local.state_machine_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

# --- IAM role -------------------------------------------------
resource "aws_iam_role" "sfn" {
  name = "${local.state_machine_name}_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

# Da tiempo a que la policy del rol propague antes de que Step Functions valide
# la state machine: con ecs:runTask.sync, UpdateStateMachine chequea de forma
# sincrona que el rol pueda crear la managed-rule de EventBridge y falla con
# "not authorized to create managed-rule" si pega con una vista vieja de IAM.
resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy.sfn]
  create_duration = "15s"
}

resource "aws_iam_role_policy" "sfn" {
  name = "${local.state_machine_name}_policy"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunPipelineTasks"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/${var.ecs_task_definition_family}:*"
        Condition = {
          ArnEquals = { "ecs:cluster" = var.ecs_cluster_arn }
        }
      },
      {
        # ecs:runTask.sync usa StopTask (aborto) y DescribeTasks (fallback de
        # polling); no soportan permisos a nivel de recurso.
        Sid      = "ManagePipelineTasks"
        Effect   = "Allow"
        Action   = ["ecs:StopTask", "ecs:DescribeTasks"]
        Resource = "*"
      },
      {
        # La integracion .sync crea/actualiza esta regla gestionada de
        # EventBridge para recibir los eventos de cambio de estado de la task.
        Sid      = "EcsSyncEventBridge"
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
      },
      {
        Sid      = "PassEcsRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [var.ecs_task_role_arn, var.ecs_execution_role_arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        Sid      = "JobStatus"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:PutItem"]
        Resource = var.dynamodb_table_arn
      },
      {
        # EnsureModelUp / CheckModel: prende el servidor de inferencia al
        # arrancar el pipeline (el apagado por inactividad lo hace el Lambda
        # del modulo qwen_autoscaler).
        Sid    = "ScaleModelService"
        Effect = "Allow"
        Action = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = [
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster_name}/${var.model_service_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- State machine ------------------------------------------
resource "aws_sfn_state_machine" "analysis" {
  name       = local.state_machine_name
  role_arn   = aws_iam_role.sfn.arn
  type       = "STANDARD"
  depends_on = [time_sleep.iam_propagation]

  # jsonencode omite las claves con valor null, por eso el centinela "@@NULL@@"
  # (ResultPath) se sustituye por un null literal, que en ASL significa
  # "descarta el resultado, pasa el input tal cual".
  definition = replace(
    jsonencode({
      Comment        = "Source Trace - pipeline de analisis (5 pasos secuenciales en ECS)"
      StartAt        = "MarkRunning"
      TimeoutSeconds = var.execution_timeout_seconds
      States         = local.states
    }),
    "\"@@NULL@@\"",
    "null"
  )

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = local.tags
}
