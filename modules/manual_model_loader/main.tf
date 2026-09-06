# ------------------------------------------------------------------
# EC2 auxiliar y descartable para cargar/actualizar a mano los pesos
# del modelo en el model-efs (el filesystem solo es alcanzable desde
# dentro de la VPC, no se puede montar desde una laptop).
#
# Flujo de uso:
#   1. enable_manual_model_loader = true  -> terraform apply
#   2. Session Manager a la instancia (sale en el output ssm_command)
#   3. El model-efs ya viene montado en /mnt/model por el user_data.
#      Descargar el .gguf ahi (ver output download_hint).
#   4. enable_manual_model_loader = false -> terraform apply (la borra)
#
# Va en el mismo SG que las tareas ECS: ese SG ya tiene abierto el
# 2049 hacia el model-efs y egress a internet/AWS APIs (SSM + HF).
# ------------------------------------------------------------------

locals {
  count = var.enabled ? 1 : 0
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "manual-model-loader"
  }
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- IAM: rol solo para Session Manager (sin claves SSH, sin bastion) ---
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count              = local.count
  name               = "${var.name}_manual_model_loader_role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = local.count
  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  count = local.count
  name  = "${var.name}_manual_model_loader_profile"
  role  = aws_iam_role.this[0].name
  tags  = local.tags
}

# --- EC2 -----------------------------------------------------------
resource "aws_instance" "this" {
  count                  = local.count
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.this[0].name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y amazon-efs-utils python3-pip tmux
    mkdir -p /mnt/model
    # Reintenta: los mount targets pueden tardar unos segundos en resolver.
    for i in $(seq 1 10); do
      mount -t efs -o tls,accesspoint=${var.model_efs_access_point_id} ${var.model_efs_file_system_id} /mnt/model && break
      sleep 10
    done
    pip3 install "huggingface_hub[hf_transfer]"
  EOF

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = merge(local.tags, { Name = "${var.name}-manual-model-loader" })
}
