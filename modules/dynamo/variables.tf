variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "table_name" {
  description = "Nombre de la tabla DynamoDB de resultados"
  type        = string
  default     = "source_trace_db"
}
