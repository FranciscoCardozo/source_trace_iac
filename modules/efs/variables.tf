variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "purpose" {
  description = "Identifica este EFS entre los varios que puede tener el proyecto (ej: \"repo\", \"model\") - se usa para nombres/tags"
  type        = string
}

variable "vpc_id" {
  description = "VPC donde corren las tareas ECS (mismo lugar que el EFS)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subredes privadas donde corren las tareas ECS - se crea un mount target por cada una"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group de las tareas ECS; se le abre 2049 (NFS) hacia el EFS"
  type        = string
}

variable "posix_uid" {
  description = "UID POSIX del access point"
  type        = number
  default     = 1000
}

variable "posix_gid" {
  description = "GID POSIX del access point"
  type        = number
  default     = 1000
}

variable "root_directory_path" {
  description = "Directorio raiz del access point dentro del EFS"
  type        = string
}
