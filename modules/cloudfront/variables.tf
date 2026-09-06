variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "web_ui_bucket_id" {
  description = "ID del bucket del web UI"
  type        = string
}

variable "web_ui_bucket_arn" {
  description = "ARN del bucket del web UI"
  type        = string
}

variable "web_ui_bucket_regional_domain_name" {
  description = "Regional domain name del bucket del web UI"
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

variable "results_bucket_regional_domain_name" {
  description = "Regional domain name del bucket de resultados"
  type        = string
}

variable "price_class" {
  description = "Price class de CloudFront"
  type        = string
  default     = "PriceClass_100"
}

variable "web_ui_origin_path" {
  description = "Prefijo del bucket del web UI que sirve CloudFront. El workflow del repo hace 'aws s3 sync ... s3://<bucket>/app/', asi que la distribucion lee de /app."
  type        = string
  default     = "/app"
}
