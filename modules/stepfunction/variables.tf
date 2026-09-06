variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nombre de SOURCE_TRACE_DB"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN de SOURCE_TRACE_DB"
  type        = string
}

# --- ECS: cada paso del pipeline es una task Fargate efimera ----------
variable "ecs_cluster_arn" {
  description = "ARN del cluster ECS donde se lanzan las tasks de cada paso"
  type        = string
}

variable "ecs_task_definition_family" {
  description = "Familia del task definition del analysis-mngr (Step Functions usa la ultima revision ACTIVE)"
  type        = string
}

variable "ecs_container_name" {
  description = "Nombre del contenedor en el task definition (destino de los overrides de entorno por paso)"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN del task role del analysis-mngr (Step Functions necesita iam:PassRole sobre el)"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ARN del execution role del analysis-mngr (iam:PassRole)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subredes privadas donde corren las tasks de cada paso"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group de las tasks (mismo que usa qwen-inference, para poder llamarlo)"
  type        = string
}

variable "pipeline_steps" {
  description = "Pasos del analisis, en orden. Cada uno se ejecuta como una task Fargate con el env jobType = <paso>."
  type        = list(string)
  default     = ["getSource", "basicAnalysis", "functionalResume", "componentAnalysis", "arquitectureAnalysis"]
}

variable "step_timeout_seconds" {
  description = "Timeout maximo de un paso individual antes de marcar el job como FAILED"
  type        = number
  default     = 3600
}

variable "max_retries" {
  description = "Reintentos de un paso ante States.TaskFailed (errores transitorios de ECS se reintentan aparte)"
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "Retencion del log group de la state machine"
  type        = number
  default     = 30
}
