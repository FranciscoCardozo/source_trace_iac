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

# --- Red ----------------------------------------------------------
variable "private_subnet_ids" {
  description = "Subredes privadas donde corren las tareas"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group de las tareas"
  type        = string
}

# --- Contenedor / modelo ----------------------------------------
variable "container_image" {
  description = "Imagen del worker + modelo Qwen"
  type        = string
}

variable "model_name" {
  description = "Identificador del modelo Qwen"
  type        = string
}

variable "model_service_url" {
  description = "URL interna del servidor de inferencia (servicio qwen-inference via Cloud Map)"
  type        = string
  default     = "http://qwen-inference.source-trace.local:3001"
}

variable "task_cpu" {
  description = "vCPU de la task (1024 = 1 vCPU)"
  type        = number
  default     = 4096
}

variable "task_memory" {
  description = "Memoria de la task en MB"
  type        = number
  default     = 16384
}

# --- Integracion ----------------------------------------------
variable "dynamodb_table_arn" {
  description = "ARN de SOURCE_TRACE_DB"
  type        = string
}

variable "results_bucket_arn" {
  description = "ARN del bucket de resultados"
  type        = string
}

variable "results_bucket_id" {
  description = "Nombre/ID del bucket de resultados"
  type        = string
}

variable "upload_bucket_arn" {
  description = "ARN del bucket de subida de codigo fuente (el worker lo lee)"
  type        = string
}

variable "upload_bucket_id" {
  description = "Nombre/ID del bucket de subida de codigo fuente"
  type        = string
}

variable "log_retention_days" {
  description = "Retencion del log group del ECS"
  type        = number
  default     = 30
}

# --- EFS repo-efs (compartido, lectura-escritura, entre pasos del pipeline)
variable "repo_efs_file_system_id" {
  description = "ID del EFS repo-efs"
  type        = string
}

variable "repo_efs_file_system_arn" {
  description = "ARN del EFS repo-efs (recurso de la policy IAM ClientMount/ClientWrite)"
  type        = string
}

variable "repo_efs_access_point_id" {
  description = "ID del access point de lectura-escritura del repo-efs"
  type        = string
}

variable "repo_efs_access_point_arn" {
  description = "ARN del access point de lectura-escritura (condicion de la policy IAM)"
  type        = string
}

# --- EFS model-efs (pesos del modelo Qwen, solo lectura) --------
variable "model_efs_file_system_id" {
  description = "ID del EFS model-efs"
  type        = string
}

variable "model_efs_file_system_arn" {
  description = "ARN del EFS model-efs (recurso de la policy IAM ClientMount)"
  type        = string
}

variable "model_efs_access_point_id" {
  description = "ID del access point de solo lectura del model-efs"
  type        = string
}

variable "model_efs_access_point_arn" {
  description = "ARN del access point de solo lectura (condicion de la policy IAM)"
  type        = string
}

variable "model_path" {
  description = "Ruta del archivo del modelo dentro de /mnt/model (env MODEL_PATH)"
  type        = string
  default     = "/mnt/model/model.gguf"
}
