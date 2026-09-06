# ------------------------------------------------------------------
# VPC del analysis manager (ECS Fargate + Qwen)
# 2 subredes publicas (NAT) + 2 privadas (tareas ECS, sin IP publica)
# ------------------------------------------------------------------

locals {
  az_count = length(var.availability_zones)
  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.name}_vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${var.name}_igw" })
}

# --- Subredes publicas -------------------------------------------------
resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${var.name}_public_${var.availability_zones[count.index]}" })
}

# --- Subredes privadas -----------------------------------------------
resource "aws_subnet" "private" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.tags, { Name = "${var.name}_private_${var.availability_zones[count.index]}" })
}

# --- NAT (uno solo para abaratar; las tareas salen a internet por aqui)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.name}_nat_eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(local.tags, { Name = "${var.name}_nat" })

  depends_on = [aws_internet_gateway.main]
}

# --- Route tables ---------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, { Name = "${var.name}_public_rt" })
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.tags, { Name = "${var.name}_private_rt" })
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- VPC endpoint S3 (gateway, gratis: trafico ECS -> results bucket sin NAT)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.tags, { Name = "${var.name}_s3_endpoint" })
}

data "aws_region" "current" {}

# --- Security group de las tareas ECS -------------------------------
# Worker SQS: no necesita ingress, solo egress a AWS APIs / internet.
resource "aws_security_group" "ecs" {
  name        = "${var.name}_ecs_sg"
  description = "SG de las tareas ECS del analysis manager"
  vpc_id      = aws_vpc.main.id

  # El servidor de inferencia (servicio qwen-inference, puerto 3001) y sus
  # consumidores (analysis-mngr, lanzado via run-task suelto) comparten este
  # SG. Se descubren por Cloud Map (qwen-inference.source-trace.local) y hablan
  # entre si en el 3001, por eso el SG tiene que permitirse a si mismo.
  ingress {
    description = "llama.cpp inference (qwen-inference) entre tareas del cluster"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Salida a internet / AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name}_ecs_sg" })
}
