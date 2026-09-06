variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "Region AWS"
  type        = string
}

variable "alarm_email" {
  description = "Email que recibe las alarmas (vacio = sin suscripcion)"
  type        = string
  default     = ""
}

# --- Dimensiones de las metricas -------------------------------
variable "ecs_cluster_name" {
  type = string
}

variable "model_service_name" {
  description = "Nombre del ECS service del servidor de inferencia (qwen-inference)"
  type        = string
}

variable "repo_efs_id" {
  description = "FileSystemId del repo-efs (estado compartido entre pasos del pipeline)"
  type        = string
}

variable "model_efs_id" {
  description = "FileSystemId del model-efs (pesos del modelo, solo lectura)"
  type        = string
}

variable "state_machine_arn" {
  type = string
}

variable "invoker_function_name" {
  type = string
}

variable "results_function_name" {
  type = string
}

variable "scale_down_function_name" {
  description = "Nombre del Lambda que apaga qwen-inference por inactividad"
  type        = string
}
