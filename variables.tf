# ------------------------------------------------------------------
# Credenciales / cuenta
# ------------------------------------------------------------------
variable "access_key" {
  description = "AWS access key id"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "AWS account id"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region de AWS donde se despliega toda la arquitectura"
  type        = string
  default     = "us-east-1"
}

# ------------------------------------------------------------------
# Nomenclatura
# ------------------------------------------------------------------
variable "project" {
  description = "Prefijo de todos los recursos"
  type        = string
  default     = "source_trace"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "prod"
}

# ------------------------------------------------------------------
# Red
# ------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR de la VPC del analysis manager"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs para las subredes (minimo 2 para alta disponibilidad)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las subredes publicas (NAT / egress)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las subredes privadas (tareas ECS)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ------------------------------------------------------------------
# ECS / modelo Qwen
# ------------------------------------------------------------------
variable "model_container_image" {
  description = "Imagen del contenedor que corre el worker + modelo Qwen. Debe leer SQS_QUEUE_URL, RESULTS_BUCKET y DYNAMODB_TABLE del entorno."
  type        = string
  default     = "public.ecr.aws/docker/library/python:3.12-slim"
}

variable "model_name" {
  description = "Identificador del modelo Qwen a cargar dentro del contenedor"
  type        = string
  default     = "Qwen/Qwen2.5-0.5B-Instruct"
}

variable "ecs_task_cpu" {
  description = "vCPU de la task Fargate (1024 = 1 vCPU). Sin GPU dedicada por ahora."
  type        = number
  default     = 4096
}

variable "ecs_task_memory" {
  description = "Memoria de la task Fargate en MB"
  type        = number
  default     = 16384
}

# ------------------------------------------------------------------
# Subida de codigo fuente
# ------------------------------------------------------------------
variable "upload_allowed_origins" {
  description = "Origenes del front autorizados a subir al bucket de upload (CORS). Restringir en prod al dominio real."
  type        = list(string)
  default     = ["*"]
}

variable "upload_expiration_days" {
  description = "Dias tras los que se borran automaticamente los archivos subidos"
  type        = number
  default     = 30
}

# ------------------------------------------------------------------
# Observabilidad
# ------------------------------------------------------------------
variable "log_retention_days" {
  description = "Retencion de todos los log groups de CloudWatch"
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email opcional que recibe las alarmas de CloudWatch (vacio = sin suscripcion)"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------
# GitHub Actions (OIDC) - workflow "Populate Model EFS" en otro repo
# ------------------------------------------------------------------
variable "github_org" {
  description = "Organizacion/usuario de GitHub dueno del repo que corre Populate Model EFS"
  type        = string
}

variable "github_repo" {
  description = "Repo de GitHub autorizado a asumir el rol de deploy del model-loader via OIDC"
  type        = string
}

variable "github_subject_filter" {
  description = "Filtro del claim 'sub' del token OIDC (ej: 'ref:refs/heads/main', '*' = cualquier rama/ref de ese repo)"
  type        = string
  default     = "*"
}

variable "github_owner_id" {
  description = "ID numerico del owner de GitHub (el repo tiene el subject claim con IDs: repo:owner@id/repo@id:...)"
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "ID numerico del repo de GitHub"
  type        = string
  default     = ""
}

variable "enable_manual_model_loader" {
  description = "Enciende la EC2 auxiliar para cargar los pesos del modelo a mano en el model-efs. Dejar en false salvo durante esa operacion."
  type        = bool
  default     = false
}

variable "model_loader_container_name" {
  description = "Nombre del container en ecs/model-loader-task-definition.json (debe coincidir con el JSON del otro repo)"
  type        = string
  default     = "model-loader"
}

variable "app_container_name" {
  description = "Nombre del container en ecs/task-definition.json del repo mngr (debe coincidir con el \"name\" del container en ese JSON)"
  type        = string
  default     = "analysis-mngr"
}
