variable "name" {
  description = "Prefijo de nombre para los buckets"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "account_id" {
  description = "AWS account id (sufijo para nombres unicos de bucket)"
  type        = string
}

variable "versioning_enabled" {
  description = "Habilitar versionado en los buckets"
  type        = bool
  default     = true
}

variable "upload_allowed_origins" {
  description = "Origenes permitidos para el CORS del bucket de subida (el front). Restringir en prod."
  type        = list(string)
  default     = ["*"]
}

variable "upload_expiration_days" {
  description = "Dias tras los que se borran los archivos subidos"
  type        = number
  default     = 30
}
