variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "model_efs_file_system_arn" {
  description = "ARN del model-efs (recurso de la policy IAM ClientMount/ClientWrite)"
  type        = string
}

variable "model_efs_access_point_arn" {
  description = "ARN del access point del model-efs (condicion de la policy IAM)"
  type        = string
}

variable "log_retention_days" {
  description = "Retencion del log group del model-loader"
  type        = number
  default     = 30
}

variable "image_retention_count" {
  description = "Cantidad de imagenes recientes a conservar en el ECR (el resto se borra)"
  type        = number
  default     = 10
}
