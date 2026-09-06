# ------------------------------------------------------------------
# OIDC de GitHub Actions para los workflows del repo mngr:
#   - Build & Deploy ECS   (build+push imagen app, register task def, update service)
#   - Populate Model EFS    (build+push imagen model-loader, register task def, run-task)
#
# Un solo rol (secrets.AWS_DEPLOY_ROLE_ARN) para los dos workflows.
#
# El proveedor OIDC es unico por cuenta/URL - si ya existiera uno para
# token.actions.githubusercontent.com en esta cuenta (creado por otro
# Terraform), hay que importarlo en vez de crearlo.
# ------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  # Nombre estable (el modulo empezo siendo solo para el model-loader) para no
  # romper el secret AWS_DEPLOY_ROLE_ARN que ya esta configurado en el repo.
  role_name    = "${var.name}_model_loader_deploy_role"
  cluster_name = element(split("/", var.ecs_cluster_arn), 1)

  # Este repo tiene el subject claim personalizado con IDs numericos:
  #   repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
  # (si no se pasan los IDs, se usa el formato estandar repo:<owner>/<repo>:<context>)
  github_slug = (var.github_owner_id != "" && var.github_repo_id != "") ? (
    "${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
  ) : "${var.github_org}/${var.github_repo}"
  sub_pattern = "repo:${local.github_slug}:${var.github_subject_filter}"
}

# GitHub migro el cert de token.actions.githubusercontent.com de DigiCert a
# Let's Encrypt: los thumbprints hardcodeados clasicos ya no sirven. Se
# calculan dinamicamente desde la cadena real que sirve el endpoint OIDC.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = distinct(data.tls_certificate.github.certificates[*].sha1_fingerprint)

  tags = local.tags
}

resource "aws_iam_role" "deploy" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      # configure-aws-credentials pasa session tags (GitHub, Repository, Actor,
      # Branch, Commit...) en el AssumeRoleWithWebIdentity, por eso hace falta
      # tambien sts:TagSession - si no, STS rechaza con el generico
      # "Not authorized to perform sts:AssumeRoleWithWebIdentity".
      Action = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # AWS obliga a condicionar por `sub` (o `job_workflow_ref`) en los
        # proveedores OIDC de GitHub. `:*` en la parte de contexto = cualquier
        # rama/tag/environment del repo (el owner/repo sigue fijo).
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.sub_pattern
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "deploy" {
  name = "${local.role_name}_policy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = var.ecr_repository_arns
      },
      {
        # RegisterTaskDefinition / DescribeTaskDefinition no soportan
        # permisos a nivel de recurso.
        Sid      = "EcsTaskDef"
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:DeregisterTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "EcsRunTask"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/*"
        Condition = {
          ArnEquals = {
            "ecs:cluster" = var.ecs_cluster_arn
          }
        }
      },
      {
        Sid      = "EcsObserveTask"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks", "ecs:StopTask"]
        Resource = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task/${local.cluster_name}/*"
      },
      {
        Sid      = "EcsUpdateService"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = length(var.ecs_service_arns) > 0 ? var.ecs_service_arns : ["arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${local.cluster_name}/*"]
      },
      {
        Sid      = "PassEcsRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = var.pass_role_arns
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}
