# ------------------------------------------------------------------
# SOURCE_TRACE_ANALYSIS_MNGR_METRICS
# Dashboard de salud: tasks ECS del pipeline (a nivel cluster, porque
# cada paso es una task efimera lanzada por el Step Functions, no un
# servicio), ejecuciones del Step Functions y Lambdas. Mas alarmas clave.
# ------------------------------------------------------------------

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_sns_topic" "alarms" {
  name = "${var.name}_alarms"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# --- Dashboard -------------------------------------------------
locals {
  dash_region = var.region
}

resource "aws_cloudwatch_dashboard" "analysis_mngr" {
  dashboard_name = "${var.name}_analysis_mngr_metrics"

  dashboard_body = jsonencode({
    widgets = [
      # ======================= ECS: servidor de inferencia =======================
      { type = "text", x = 0, y = 0, width = 24, height = 1,
      properties = { markdown = "## ECS - servidor de inferencia (qwen-inference)  ·  on-demand: 0 cuando no hay jobs" } },

      { type = "metric", x = 0, y = 1, width = 12, height = 6,
        properties = {
          title = "qwen - CPU / Memoria (% de lo reservado)", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.model_service_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.model_service_name]
          ]
          yAxis = { left = { min = 0, max = 100 } }
      } },

      { type = "metric", x = 12, y = 1, width = 12, height = 6,
        properties = {
          title = "qwen - tasks deseadas vs corriendo (0 = apagado)", region = local.dash_region, view = "timeSeries"
          stat  = "Maximum"
          metrics = [
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.model_service_name, { label = "deseadas" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.model_service_name, { label = "corriendo" }]
          ]
      } },

      # ======================= ECS: pipeline (tasks efimeras) =======================
      { type = "text", x = 0, y = 7, width = 24, height = 1,
      properties = { markdown = "## ECS - pipeline (getSource / basicAnalysis / ...) - metricas a nivel cluster (incluyen qwen)" } },

      { type = "metric", x = 0, y = 8, width = 12, height = 6,
        properties = {
          title = "Memoria: usada vs reservada (MiB)", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", var.ecs_cluster_name, { label = "usada" }],
            ["ECS/ContainerInsights", "MemoryReserved", "ClusterName", var.ecs_cluster_name, { label = "reservada" }]
          ]
      } },

      { type = "metric", x = 12, y = 8, width = 12, height = 6,
        properties = {
          title = "CPU: usada vs reservada (unidades, 1024 = 1 vCPU)", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", var.ecs_cluster_name, { label = "usada" }],
            ["ECS/ContainerInsights", "CpuReserved", "ClusterName", var.ecs_cluster_name, { label = "reservada" }]
          ]
      } },

      { type = "metric", x = 0, y = 14, width = 12, height = 6,
        properties = {
          title = "Disco efimero: usado vs reservado (GB) - getSource clona repos aca", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "EphemeralStorageUtilized", "ClusterName", var.ecs_cluster_name, { label = "usado" }],
            ["ECS/ContainerInsights", "EphemeralStorageReserved", "ClusterName", var.ecs_cluster_name, { label = "reservado" }]
          ]
      } },

      { type = "metric", x = 12, y = 14, width = 12, height = 6,
        properties = {
          title = "Red del cluster (bytes) - descargas de repos / modelo", region = local.dash_region, view = "timeSeries"
          stat  = "Sum"
          metrics = [
            ["ECS/ContainerInsights", "NetworkRxBytes", "ClusterName", var.ecs_cluster_name, { label = "in" }],
            ["ECS/ContainerInsights", "NetworkTxBytes", "ClusterName", var.ecs_cluster_name, { label = "out" }]
          ]
      } },

      # ======================= Duracion =======================
      { type = "text", x = 0, y = 20, width = 24, height = 1,
      properties = { markdown = "## Duracion - cuanto tardan las tasks del pipeline y las ejecuciones completas" } },

      { type = "metric", x = 0, y = 21, width = 8, height = 6,
        properties = {
          title = "Duracion de cada task del pipeline (ms)", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["AWS/States", "ServiceIntegrationRunTime", "StateMachineArn", var.state_machine_arn, { stat = "Average", label = "promedio" }],
            ["AWS/States", "ServiceIntegrationRunTime", "StateMachineArn", var.state_machine_arn, { stat = "Maximum", label = "maximo" }]
          ]
      } },

      { type = "metric", x = 8, y = 21, width = 8, height = 6,
        properties = {
          title = "Duracion total de la ejecucion (ms)", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["AWS/States", "ExecutionTime", "StateMachineArn", var.state_machine_arn, { stat = "Average", label = "promedio" }],
            ["AWS/States", "ExecutionTime", "StateMachineArn", var.state_machine_arn, { stat = "Maximum", label = "maximo" }]
          ]
      } },

      { type = "metric", x = 16, y = 21, width = 8, height = 6,
        properties = {
          title = "Ejecuciones del pipeline", region = local.dash_region, view = "timeSeries", stat = "Sum"
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", var.state_machine_arn, { label = "iniciadas" }],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.state_machine_arn, { label = "ok" }],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.state_machine_arn, { label = "fallidas" }],
            ["AWS/States", "ExecutionsTimedOut", "StateMachineArn", var.state_machine_arn, { label = "timeout" }]
          ]
      } },

      # ======================= EFS =======================
      { type = "text", x = 0, y = 27, width = 24, height = 1,
      properties = { markdown = "## EFS - repo-efs (rw, compartido entre pasos) y model-efs (ro, pesos del modelo). Ambos en modo *bursting* / *generalPurpose*." } },

      { type = "metric", x = 0, y = 28, width = 12, height = 6,
        properties = {
          title = "Burst credit balance (bytes) - si llega a 0, el throughput cae al baseline", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["AWS/EFS", "BurstCreditBalance", "FileSystemId", var.repo_efs_id, { label = "repo-efs" }],
            ["AWS/EFS", "BurstCreditBalance", "FileSystemId", var.model_efs_id, { label = "model-efs" }]
          ]
      } },

      { type = "metric", x = 12, y = 28, width = 12, height = 6,
        properties = {
          title = "Permitted throughput (bytes/s) - el techo actual de lectura+escritura", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["AWS/EFS", "PermittedThroughput", "FileSystemId", var.repo_efs_id, { label = "repo-efs" }],
            ["AWS/EFS", "PermittedThroughput", "FileSystemId", var.model_efs_id, { label = "model-efs" }]
          ]
      } },

      { type = "metric", x = 0, y = 34, width = 12, height = 6,
        properties = {
          title = "% del limite de IOPS (>90 = throttling, el pipeline se frena)", region = local.dash_region, view = "timeSeries", stat = "Maximum"
          metrics = [
            ["AWS/EFS", "PercentIOLimit", "FileSystemId", var.repo_efs_id, { label = "repo-efs" }],
            ["AWS/EFS", "PercentIOLimit", "FileSystemId", var.model_efs_id, { label = "model-efs" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
      } },

      { type = "metric", x = 12, y = 34, width = 12, height = 6,
        properties = {
          title = "Clientes montados (una task = un cliente)", region = local.dash_region, view = "timeSeries", stat = "Sum"
          metrics = [
            ["AWS/EFS", "ClientConnections", "FileSystemId", var.repo_efs_id, { label = "repo-efs" }],
            ["AWS/EFS", "ClientConnections", "FileSystemId", var.model_efs_id, { label = "model-efs" }]
          ]
      } },

      { type = "metric", x = 0, y = 40, width = 12, height = 6,
        properties = {
          title = "IO por periodo (bytes) - picos de lectura = carga del modelo", region = local.dash_region, view = "timeSeries", stat = "Sum"
          metrics = [
            ["AWS/EFS", "DataReadIOBytes", "FileSystemId", var.repo_efs_id, { label = "repo read" }],
            ["AWS/EFS", "DataWriteIOBytes", "FileSystemId", var.repo_efs_id, { label = "repo write" }],
            ["AWS/EFS", "DataReadIOBytes", "FileSystemId", var.model_efs_id, { label = "model read" }]
          ]
      } },

      { type = "metric", x = 12, y = 40, width = 12, height = 6,
        properties = {
          title = "Tamano almacenado (bytes)", region = local.dash_region, view = "timeSeries"
          metrics = [
            ["AWS/EFS", "StorageBytes", "FileSystemId", var.repo_efs_id, "StorageClass", "Total", { label = "repo-efs" }],
            ["AWS/EFS", "StorageBytes", "FileSystemId", var.model_efs_id, "StorageClass", "Total", { label = "model-efs" }]
          ]
      } },

      # ======================= Lambdas =======================
      { type = "text", x = 0, y = 46, width = 24, height = 1,
      properties = { markdown = "## Lambdas - invoker (arranca el pipeline), results (consulta estado), scale-down (apaga qwen)" } },

      { type = "metric", x = 0, y = 47, width = 12, height = 6,
        properties = {
          title = "Invocaciones y errores", region = local.dash_region, view = "timeSeries", stat = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.invoker_function_name, { label = "invoker inv" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.invoker_function_name, { label = "invoker err" }],
            ["AWS/Lambda", "Invocations", "FunctionName", var.results_function_name, { label = "results inv" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.results_function_name, { label = "results err" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.scale_down_function_name, { label = "scale-down err" }]
          ]
      } },

      { type = "metric", x = 12, y = 47, width = 12, height = 6,
        properties = {
          title = "Duracion (ms)", region = local.dash_region, view = "timeSeries", stat = "Average"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.invoker_function_name, { label = "invoker" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.results_function_name, { label = "results" }]
          ]
      } }
    ]
  })
}

# --- Alarmas --------------------------------------------------
# La salud del pipeline se vigila a nivel Step Functions (sfn_failed /
# sfn_timed_out): un paso que falla o se cuelga hace fallar la ejecucion.

resource "aws_cloudwatch_metric_alarm" "invoker_errors" {
  alarm_name          = "${var.name}_invoker_lambda_errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Errores en SOURCE_TRACE_INVOKER_FUNCTION"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.invoker_function_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "results_errors" {
  alarm_name          = "${var.name}_results_lambda_errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Errores en SOURCE_TRACE_RESULTS_FUNCTION"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.results_function_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "sfn_failed" {
  alarm_name          = "${var.name}_analysis_executions_failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Ejecuciones del Step Functions workflow del analisis que terminaron en FAILED"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "sfn_timed_out" {
  alarm_name          = "${var.name}_analysis_executions_timed_out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsTimedOut"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Ejecuciones del pipeline que excedieron el timeout de un paso (task colgada)"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  tags = local.tags
}

# --- EFS ---------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "repo_efs_io_limit" {
  alarm_name          = "${var.name}_repo_efs_io_throttling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "PercentIOLimit"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 90
  alarm_description   = "repo-efs cerca del limite de IOPS (>90%) - las tasks del pipeline se estan frenando en IO"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = var.repo_efs_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "model_efs_burst_credits" {
  alarm_name          = "${var.name}_model_efs_burst_credits_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  # ~20% del maximo para un filesystem chico (< 1 TiB). Por debajo de esto el
  # throughput permitido empieza a bajar hacia el baseline.
  threshold          = 500000000000
  alarm_description  = "model-efs con pocos burst credits - las cargas del modelo van a empezar a ir mas lento"
  alarm_actions      = [aws_sns_topic.alarms.arn]
  treat_missing_data = "notBreaching"

  dimensions = {
    FileSystemId = var.model_efs_id
  }

  tags = local.tags
}
