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

variable "model_service_name" {
  description = "Nombre del ECS service del servidor de inferencia. El pipeline lo escala a 1 (EnsureModelUp) antes de empezar; se apaga solo por inactividad (modulo qwen_autoscaler)."
  type        = string
}

variable "ecs_cluster_name" {
  description = "Nombre del cluster ECS (para construir el ARN del service en la policy)"
  type        = string
}

variable "model_warmup_seconds" {
  description = "Espera fija tras confirmar que la task de inferencia esta RUNNING, para que llama.cpp termine de cargar el modelo"
  type        = number
  default     = 30
}

variable "execution_timeout_seconds" {
  description = "Timeout total de una ejecucion del pipeline (incluye el warmup del modelo y los 5 pasos)"
  type        = number
  default     = 10800
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
