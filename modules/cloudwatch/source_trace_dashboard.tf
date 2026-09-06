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
resource "aws_cloudwatch_dashboard" "analysis_mngr" {
  dashboard_name = "${var.name}_analysis_mngr_metrics"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS pipeline - CPU / Memoria usadas (cluster)"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", var.ecs_cluster_name],
            ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", var.ecs_cluster_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS pipeline - Tasks en el cluster (Container Insights)"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "TaskCount", "ClusterName", var.ecs_cluster_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Step Functions - Ejecuciones"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", var.state_machine_arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.state_machine_arn],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.state_machine_arn],
            ["AWS/States", "ExecutionsTimedOut", "StateMachineArn", var.state_machine_arn]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Step Functions - Duracion de ejecucion (ms)"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          metrics = [
            ["AWS/States", "ExecutionTime", "StateMachineArn", var.state_machine_arn]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Lambdas - Invocaciones y errores"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.invoker_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.invoker_function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", var.results_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.results_function_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Lambdas - Duracion (ms)"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.invoker_function_name],
            ["AWS/Lambda", "Duration", "FunctionName", var.results_function_name]
          ]
        }
      }
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
