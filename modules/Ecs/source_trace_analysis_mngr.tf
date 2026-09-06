# ------------------------------------------------------------------
# SOURCE_TRACE_ANALYSIS_MNGR
# Cluster ECS Fargate + task definition de los pasos del pipeline de
# analisis. Cada paso (getSource, basicAnalysis, ...) lo lanza el Step
# Functions workflow como una task efimera de esta familia, pasando el
# nombre del paso en el env jobType. El contenedor llama al servicio de
# inferencia (qwen-inference.source-trace.local:3001) por HTTP.
#
# No hay SQS ni autoscaling: la orquestacion es 100% del Step Functions
# (ecs:runTask.sync paso por paso). El aws_ecs_service queda en
# desired_count 0 - existe solo como destino del workflow de CI y para
# exponer cluster/roles; las tasks reales las corre el Step Functions.
#
# EFS montado via access point (iam = ENABLED):
#   - repo-efs  (/mnt/repo,  read-write) - estado compartido entre pasos
#   - model-efs (/mnt/model, read-only)  - por si un paso lee pesos directo
# ------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  family = "${var.name}_analysis_mngr"
}

# --- Logs (SOURCE_TRACE_ANALYSIS_MNGR_LOGS) -----------------------
resource "aws_cloudwatch_log_group" "analysis_mngr" {
  name              = "/ecs/${local.family}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

# --- Cluster ---------------------------------------------------
resource "aws_ecs_cluster" "analysis_mngr" {
  name = "${var.name}_analysis_mngr"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

resource "aws_ecs_cluster_capacity_providers" "analysis_mngr" {
  cluster_name       = aws_ecs_cluster.analysis_mngr.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# --- IAM: execution role (pull de imagen + logs) ----------------
resource "aws_iam_role" "execution" {
  name = "${local.family}_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# AmazonECSTaskExecutionRolePolicy no incluye logs:CreateLogGroup. Las task
# definitions que registra el repo mngr por su cuenta (qwen-inference,
# analysis-mngr) usan awslogs-create-group=true, asi que el exec role - que
# es compartido - necesita poder crear el log group o el task no arranca
# (TaskFailedToStart: ResourceInitializationError ... logs:CreateLogGroup).
resource "aws_iam_role_policy" "execution_create_log_group" {
  name = "qwen_inference_exec_logs"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/*"
    }]
  })
}

# --- IAM: task role (permisos de la app) ------------------------
resource "aws_iam_role" "task" {
  name = "${local.family}_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "task" {
  name = "${local.family}_task_policy"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [var.dynamodb_table_arn, "${var.dynamodb_table_arn}/index/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [var.results_bucket_arn, "${var.results_bucket_arn}/*"]
      },
      {
        # Lee el codigo fuente que subio el front para analizarlo.
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [var.upload_bucket_arn, "${var.upload_bucket_arn}/*"]
      },
      {
        # repo-efs: montado en /mnt/repo, compartido entre los pasos del
        # pipeline (getSource escribe, los pasos siguientes leen). El
        # volumen usa iam = ENABLED, por eso esta condicion contra el
        # access point de lectura-escritura.
        Effect   = "Allow"
        Action   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
        Resource = var.repo_efs_file_system_arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = var.repo_efs_access_point_arn
          }
        }
      },
      {
        # model-efs: montado read-only en /mnt/model. Sin ClientWrite a
        # proposito - el mountPoint tambien tiene readOnly = true.
        Effect   = "Allow"
        Action   = ["elasticfilesystem:ClientMount"]
        Resource = var.model_efs_file_system_arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = var.model_efs_access_point_arn
          }
        }
      }
    ]
  })
}

# --- Task definition -----------------------------------------
resource "aws_ecs_task_definition" "analysis_mngr" {
  family                   = local.family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # repo-efs: volumen compartido de lectura-escritura entre los pasos del
  # pipeline (Fargate requiere platform version >= 1.4.0 para EFS; "LATEST",
  # el default del servicio, ya cumple esto).
  volume {
    name = "repo-efs"

    efs_volume_configuration {
      file_system_id     = var.repo_efs_file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.repo_efs_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  # model-efs: pesos del modelo Qwen, solo lectura.
  volume {
    name = "model-efs"

    efs_volume_configuration {
      file_system_id     = var.model_efs_file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.model_efs_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "analysis-mngr"
      image     = var.container_image
      essential = true

      # jobType y JOB_ID los inyecta el Step Functions como override por paso.
      environment = [
        { name = "RESULTS_BUCKET", value = var.results_bucket_id },
        { name = "UPLOAD_BUCKET", value = var.upload_bucket_id },
        { name = "MODEL_NAME", value = var.model_name },
        { name = "AWS_REGION", value = var.region },
        { name = "MODEL_SERVICE_URL", value = var.model_service_url },
        # Directorio de trabajo del job dentro de repo-efs: /mnt/repo/<JOB_ID>.
        { name = "WORKDIR", value = "/mnt/repo" },
        { name = "MODEL_PATH", value = var.model_path }
      ]

      mountPoints = [
        {
          sourceVolume  = "repo-efs"
          containerPath = "/mnt/repo"
          readOnly      = false
        },
        {
          sourceVolume  = "model-efs"
          containerPath = "/mnt/model"
          readOnly      = true
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.analysis_mngr.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "analysis-mngr"
        }
      }
    }
  ])

  lifecycle {
    # El contenido del contenedor (imagen, env, command) lo administra el repo
    # mngr via `aws ecs register-task-definition` (ecs/task-definition.json).
    # Terraform solo deja una revision de arranque; el Step Functions corre
    # siempre la ultima revision ACTIVE de la familia.
    ignore_changes = [container_definitions]
  }

  tags = local.tags
}

# --- Service -------------------------------------------------
resource "aws_ecs_service" "analysis_mngr" {
  name            = "${var.name}_analysis_mngr"
  cluster         = aws_ecs_cluster.analysis_mngr.id
  task_definition = aws_ecs_task_definition.analysis_mngr.arn
  desired_count   = 0
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    # Las tasks reales del pipeline las lanza el Step Functions (runTask.sync),
    # no este servicio - queda en 0. task_definition lo puede tocar el workflow
    # de CI; Terraform solo deja la revision de arranque.
    ignore_changes = [desired_count, task_definition]
  }

  tags = local.tags
}
