variable "name" {
  description = "Prefijo de nombre"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "enabled" {
  description = "Crea la EC2 auxiliar. Dejar en false salvo cuando se necesita cargar/actualizar el modelo a mano."
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "Subnet (privada, con NAT) donde vive la EC2 auxiliar - debe tener mount target del model-efs"
  type        = string
}

variable "security_group_id" {
  description = "SG de las tareas ECS: ya tiene permitido el 2049 hacia el model-efs y egress a internet"
  type        = string
}

variable "model_efs_file_system_id" {
  description = "ID del model-efs a montar"
  type        = string
}

variable "model_efs_access_point_id" {
  description = "Access point del model-efs (raiz /model, uid/gid 1000)"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia. t3.medium alcanza para descargar; el cuello de botella es la red."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "GB del EBS root. Se baja directo al EFS, pero deja margen para el cache de huggingface_hub."
  type        = number
  default     = 60
}
