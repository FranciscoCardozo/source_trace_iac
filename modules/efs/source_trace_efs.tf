# ------------------------------------------------------------------
# EFS generico, instanciado una vez por proposito (var.purpose):
#
#   - "repo"  -> compartido de lectura-escritura entre los pasos del
#                pipeline de analisis (getSource escribe, los pasos
#                siguientes leen). Cada task de ECS es efimera (Fargate) -
#                el codigo descargado no sobrevive entre pasos si no vive
#                en un volumen compartido como este.
#   - "model" -> pesos del modelo Qwen, montado solo lectura en /mnt/model
#                (el mount readOnly y los permisos IAM del modulo Ecs son
#                los que hacen que sea de solo lectura, no este modulo).
#
# NOTA: los labels de los recursos ("repo"/"repo_rw") quedaron fijos por
# compatibilidad con el repo-efs que ya esta desplegado (evita reemplazarlo
# al reusar este modulo para el model-efs) - son solo el nombre interno del
# recurso en Terraform, no aparecen en AWS.
# ------------------------------------------------------------------

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_efs_file_system" "repo" {
  creation_token = "${var.name}-${var.purpose}-efs"
  encrypted      = true

  # Costo: a los 30 dias sin acceso pasa a Infrequent Access; si se vuelve a
  # leer, vuelve a Standard. No borra nada - ver nota de limpieza en el README.
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(local.tags, { Name = "${var.name}_${var.purpose}_efs" })
}

# --- Security group: NFS (2049) solo desde las tareas ECS de este cluster
resource "aws_security_group" "efs" {
  name        = "${var.name}_${var.purpose}_efs_sg"
  description = "Permite NFS (2049) desde las tareas ECS hacia el ${var.purpose}-efs"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS desde las tareas ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name}_${var.purpose}_efs_sg" })
}

# --- Mount target por cada subred privada donde corren las tareas ---
resource "aws_efs_mount_target" "repo" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.repo.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# --- Access point ------------------------------------------------
# iam = ENABLED en el volumen del task definition obliga a autenticar via
# IAM (el task role necesita elasticfilesystem:ClientMount, y ademas
# ClientWrite si es de lectura-escritura, condicionado a este AccessPointArn
# - ver modules/Ecs).
resource "aws_efs_access_point" "repo_rw" {
  file_system_id = aws_efs_file_system.repo.id

  posix_user {
    uid = var.posix_uid
    gid = var.posix_gid
  }

  root_directory {
    path = var.root_directory_path

    creation_info {
      owner_uid   = var.posix_uid
      owner_gid   = var.posix_gid
      permissions = "0755"
    }
  }

  tags = merge(local.tags, { Name = "${var.name}_${var.purpose}_efs_ap" })
}
