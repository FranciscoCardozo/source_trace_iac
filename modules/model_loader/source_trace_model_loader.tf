# ------------------------------------------------------------------
# Infra para el workflow "Populate Model EFS" (vive en otro repo, via
# GitHub Actions): build+push de la imagen model-loader, ECS run-task
# one-off que baja el .gguf de HuggingFace y lo escribe en model-efs.
#
# El task definition del model-loader (ecs/model-loader-task-definition.json)
# lo registra el propio workflow con `aws ecs register-task-definition`
# (patron ya usado en ese repo) - Terraform no lo administra, solo los
# recursos de soporte: ECR, roles IAM y log group.
# ------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  loader_name = "${var.name}_model_loader"
}

# --- ECR: imagen del model-loader --------------------------------
resource "aws_ecr_repository" "model_loader" {
  name                 = replace(local.loader_name, "_", "-")
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "model_loader" {
  repository = aws_ecr_repository.model_loader.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar solo las ${var.image_retention_count} imagenes mas recientes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.image_retention_count
      }
      action = { type = "expire" }
    }]
  })
}

# --- Logs ----------------------------------------------------
resource "aws_cloudwatch_log_group" "model_loader" {
  name              = "/ecs/${replace(local.loader_name, "_", "-")}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

# --- IAM: execution role (pull de imagen + logs) ----------------
resource "aws_iam_role" "execution" {
  name = "${local.loader_name}_exec_role"
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

# AmazonECSTaskExecutionRolePolicy trae CreateLogStream/PutLogEvents pero NO
# CreateLogGroup. El workflow registra el task def por su cuenta y puede
# apuntar a un log group que todavia no exista (o usar awslogs-create-group);
# sin esto el task muere con "TaskFailedToStart: ... logs:CreateLogGroup".
resource "aws_iam_role_policy" "execution_logs" {
  name = "${local.loader_name}_exec_logs"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/ecs/*"
    }]
  })
}

# --- IAM: task role (escribe en model-efs) -----------------------
resource "aws_iam_role" "task" {
  name = "${local.loader_name}_task_role"
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
  name = "${local.loader_name}_task_policy"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Unico rol con permiso de escritura sobre el model-efs - el task
        # role del analysis manager solo tiene ClientMount (solo lectura).
        Effect   = "Allow"
        Action   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
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
