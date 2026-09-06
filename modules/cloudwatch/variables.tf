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

variable "state_machine_arn" {
  type = string
}

variable "invoker_function_name" {
  type = string
}

variable "results_function_name" {
  type = string
}
