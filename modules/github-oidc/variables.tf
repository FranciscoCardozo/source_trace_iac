variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "github_org" {
  description = "Organizacion/usuario de GitHub dueno del repo que corre los workflows"
  type        = string
}

variable "github_repo" {
  description = "Repo de GitHub autorizado a asumir este rol via OIDC"
  type        = string
}

variable "github_subject_filter" {
  description = "Filtro del claim 'sub' del token OIDC (ej: 'ref:refs/heads/main', 'environment:prod', '*' = cualquier ref/rama de ese repo)"
  type        = string
  default     = "*"
}

variable "github_owner_id" {
  description = "ID numerico del owner de GitHub. Si se setea (junto con github_repo_id), la trust usa el formato de sub personalizado 'repo:owner@ownerid/repo@repoid:...'. Vacio = formato estandar 'repo:owner/repo:...'."
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "ID numerico del repo de GitHub (ver github_owner_id)"
  type        = string
  default     = ""
}

# --- Permisos que necesitan los workflows del repo mngr --------------
#   - Build & Deploy ECS  : push a ECR de la app + register task def + update service
#   - Populate Model EFS   : push a ECR del model-loader + register task def + run-task
variable "ecr_repository_arns" {
  description = "ARNs de los ECR a los que hace push GitHub Actions (app + model-loader)"
  type        = list(string)
}

variable "ecs_cluster_arn" {
  description = "ARN del cluster ECS (condicion de RunTask y prefijo de los task ARNs)"
  type        = string
}

variable "ecs_service_arns" {
  description = "ARNs de los servicios ECS que actualiza Build & Deploy ECS (UpdateService/DescribeServices)"
  type        = list(string)
  default     = []
}

variable "pass_role_arns" {
  description = "Roles que los workflows pueden pasar a ECS (task + execution de app y de model-loader)"
  type        = list(string)
}

# --- Deploy via OIDC de repos que no son el mngr (Lambdas, frontend) ------
variable "deploy_subject_filter" {
  description = "Filtro del claim 'sub' para los roles de deploy de Lambdas y frontend (por defecto: solo push a main)"
  type        = string
  default     = "ref:refs/heads/main"
}

variable "lambda_deploy_targets" {
  description = <<-EOT
    Repos de Lambdas que despliegan via OIDC. Clave = alias corto (aparece en el
    nombre del rol y en el output). Cada valor:
      github_repo    - nombre del repo en GitHub
      github_repo_id - ID numerico del repo (subject claim personalizado; "" = formato estandar)
      function_arn   - ARN de la Lambda que ese repo actualiza
  EOT
  type = map(object({
    github_repo    = string
    github_repo_id = string
    function_arn   = string
  }))
  default = {}
}

variable "frontend_deploy_targets" {
  description = <<-EOT
    Repos de frontend que despliegan a S3 + CloudFront via OIDC. Clave = alias.
    Cada valor:
      github_repo                - nombre del repo en GitHub
      github_repo_id             - ID numerico del repo
      bucket_arn                 - ARN del bucket S3 destino (aws s3 sync --delete)
      cloudfront_distribution_arn - ARN de la distribucion (cloudfront:CreateInvalidation)
  EOT
  type = map(object({
    github_repo                 = string
    github_repo_id              = string
    bucket_arn                  = string
    cloudfront_distribution_arn = string
  }))
  default = {}
}
