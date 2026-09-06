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

variable "stage_name" {
  description = "Nombre del stage de ambos APIs"
  type        = string
  default     = "prod"
}

variable "log_retention_days" {
  description = "Retencion de los log groups de acceso"
  type        = number
  default     = 30
}

# ------------------------------------------------------------------
# Cada API se define enteramente por su OAS en definitions/ y apunta a una
# sola Lambda via el placeholder $${lambda_arn}, que se resuelve con
# templatefile(). Un archivo .tf por API:
#   - source_trace_api.tf           Api_source_trace.json           -> invoker
#   - source_trace_response_api.tf  Api_source_trace_response.json  -> response
# ------------------------------------------------------------------

variable "invoker_lambda_arn" {
  description = "ARN de SOURCE_TRACE_INVOKER_FUNCTION (placeholder $${lambda_arn} en Api_source_trace.json)"
  type        = string
}

variable "invoker_lambda_name" {
  description = "Nombre de SOURCE_TRACE_INVOKER_FUNCTION"
  type        = string
}

variable "response_lambda_arn" {
  description = "ARN de SOURCE_TRACE_RESPONSE_FUNCTION (placeholder $${lambda_arn} en Api_source_trace_response.json)"
  type        = string
}

variable "response_lambda_name" {
  description = "Nombre de SOURCE_TRACE_RESPONSE_FUNCTION"
  type        = string
}
