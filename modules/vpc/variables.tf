variable "name" {
  description = "Prefijo de nombre para los recursos de red"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "cidr_block" {
  description = "CIDR de la VPC"
  type        = string
}

variable "availability_zones" {
  description = "AZs para las subredes (minimo 2)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las subredes publicas"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las subredes privadas"
  type        = list(string)
}
