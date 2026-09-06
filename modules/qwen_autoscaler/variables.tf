variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN de la state machine del pipeline (para ver ejecuciones en curso)"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN del cluster ECS donde vive el servicio qwen-inference"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Nombre del cluster ECS"
  type        = string
}

variable "model_service_name" {
  description = "Nombre del ECS service del servidor de inferencia (qwen-inference)"
  type        = string
}

variable "idle_minutes" {
  description = "Minutos sin ejecuciones antes de apagar el modelo"
  type        = number
  default     = 10
}

variable "check_interval_minutes" {
  description = "Cada cuanto corre el chequeo de inactividad"
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = "Retencion del log group del Lambda"
  type        = number
  default     = 14
}
