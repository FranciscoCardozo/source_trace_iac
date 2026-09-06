variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "runtime" {
  description = "Runtime de las Lambdas"
  type        = string
  default     = "nodejs20.x"
}

variable "log_retention_days" {
  description = "Retencion de los log groups de las Lambdas"
  type        = number
  default     = 30
}

# --- Integracion con el resto de la arquitectura -------------------
variable "state_machine_arn" {
  description = "ARN del Step Functions workflow que arranca la Lambda invoker"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nombre de la tabla SOURCE_TRACE_DB"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN de la tabla SOURCE_TRACE_DB"
  type        = string
}

variable "results_bucket_id" {
  description = "ID del bucket de resultados"
  type        = string
}

variable "results_bucket_arn" {
  description = "ARN del bucket de resultados"
  type        = string
}

variable "results_cdn_domain" {
  description = "Dominio de SOURCE_TRACE_RESULTS_CLOUDFRONT (para construir URLs publicas)"
  type        = string
}

variable "upload_bucket_id" {
  description = "ID del bucket de subida de codigo fuente"
  type        = string
}

variable "upload_bucket_arn" {
  description = "ARN del bucket de subida de codigo fuente"
  type        = string
}
