# ==================================================================
# Source Trace - Analysis Manager con Qwen en AWS
#
#   CloudFront (web UI)  ->  S3 web_ui
#   CloudFront (results) ->  S3 results
#   API Gateway  ->  Lambda invoker  ->  StartExecution     (responde 202, el front no espera)
#   Step Functions  ->  DynamoDB RUNNING
#                   ->  SQS invoker (waitForTaskToken)  ->  ECS Fargate (Qwen)
#                                                            |-> DynamoDB (SOURCE_TRACE_DB)
#                                                            |-> S3 results
#                   ->  DynamoDB SUCCEEDED / FAILED
#   API Gateway  ->  Lambda results  ->  DynamoDB + S3 results
#   CloudWatch: log group por Lambda y por ECS + dashboard de salud del ECS
# ==================================================================

provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

data "aws_caller_identity" "current" {}

locals {
  prefix = var.project
}

# --- Red --------------------------------------------------------
module "vpc" {
  source               = "./modules/vpc"
  name                 = local.prefix
  environment          = var.environment
  cidr_block           = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# --- Almacenamiento -------------------------------------------
module "s3" {
  source      = "./modules/s3"
  name        = local.prefix
  environment = var.environment
  account_id  = data.aws_caller_identity.current.account_id

  upload_allowed_origins = var.upload_allowed_origins
  upload_expiration_days = var.upload_expiration_days
}

module "dynamo" {
  source      = "./modules/dynamo"
  name        = local.prefix
  environment = var.environment
}

# --- CDN -----------------------------------------------------
module "cloudfront" {
  source      = "./modules/cloudfront"
  name        = local.prefix
  environment = var.environment

  web_ui_bucket_id                   = module.s3.web_ui_bucket_id
  web_ui_bucket_arn                  = module.s3.web_ui_bucket_arn
  web_ui_bucket_regional_domain_name = module.s3.web_ui_bucket_regional_domain_name

  results_bucket_id                   = module.s3.results_bucket_id
  results_bucket_arn                  = module.s3.results_bucket_arn
  results_bucket_regional_domain_name = module.s3.results_bucket_regional_domain_name
}

# --- Orquestacion (Step Functions) ------------------------
# El workflow lanza cada paso del analisis como una task Fargate efimera
# (ecs:runTask.sync) de la familia del analysis-mngr. No hay SQS.
module "stepfunction" {
  source      = "./modules/stepfunction"
  name        = local.prefix
  environment = var.environment

  dynamodb_table_name = module.dynamo.table_name
  dynamodb_table_arn  = module.dynamo.table_arn

  ecs_cluster_arn            = module.ecs.cluster_arn
  ecs_cluster_name           = module.ecs.cluster_name
  ecs_task_definition_family = module.ecs.task_definition_family
  ecs_container_name         = var.app_container_name
  ecs_task_role_arn          = module.ecs.task_role_arn
  ecs_execution_role_arn     = module.ecs.execution_role_arn
  private_subnet_ids         = module.vpc.private_subnet_ids
  security_group_id          = module.vpc.ecs_security_group_id

  # El pipeline prende qwen-inference al arrancar (EnsureModelUp).
  model_service_name = var.model_service_name

  log_retention_days = var.log_retention_days
}

# --- Apagado por inactividad del servidor de inferencia --------------
module "qwen_autoscaler" {
  source      = "./modules/qwen_autoscaler"
  name        = local.prefix
  environment = var.environment

  state_machine_arn  = module.stepfunction.state_machine_arn
  ecs_cluster_arn    = module.ecs.cluster_arn
  ecs_cluster_name   = module.ecs.cluster_name
  model_service_name = var.model_service_name
}

# --- Lambdas -----------------------------------------------
module "lambda" {
  source             = "./modules/lambda"
  name               = local.prefix
  environment        = var.environment
  log_retention_days = var.log_retention_days

  state_machine_arn = module.stepfunction.state_machine_arn

  dynamodb_table_name = module.dynamo.table_name
  dynamodb_table_arn  = module.dynamo.table_arn

  results_bucket_id  = module.s3.results_bucket_id
  results_bucket_arn = module.s3.results_bucket_arn
  results_cdn_domain = module.cloudfront.results_domain_name

  upload_bucket_id  = module.s3.upload_bucket_id
  upload_bucket_arn = module.s3.upload_bucket_arn
}

# --- EFS repo-efs: storage compartido r/w entre pasos del pipeline -----
module "efs" {
  source      = "./modules/efs"
  name        = local.prefix
  environment = var.environment
  purpose     = "repo"

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.vpc.ecs_security_group_id
  root_directory_path   = "/repo"
}

# --- EFS model-efs: pesos del modelo Qwen, solo lectura -----------------
# El mount se hace read-only y el task role solo tiene ClientMount (sin
# ClientWrite) - ver modules/Ecs. Este modulo no impone el solo-lectura,
# solo aprovisiona el filesystem/access point.
#
# El filesystem se crea vacio: hay que poblarlo aparte (una task o instancia
# temporal con permiso de escritura, DataSync, etc.) antes de que la app
# pueda leer /mnt/model/model.gguf.
module "efs_model" {
  source      = "./modules/efs"
  name        = local.prefix
  environment = var.environment
  purpose     = "model"

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.vpc.ecs_security_group_id
  root_directory_path   = "/model"
}

# --- EC2 auxiliar para cargar el modelo a mano en el model-efs -------
# Normalmente apagado (enable_manual_model_loader = false). Encender solo
# cuando hay que subir/actualizar los pesos sin pasar por el workflow.
module "manual_model_loader" {
  source      = "./modules/manual_model_loader"
  name        = local.prefix
  environment = var.environment
  enabled     = var.enable_manual_model_loader

  subnet_id         = module.vpc.private_subnet_ids[0]
  security_group_id = module.vpc.ecs_security_group_id

  model_efs_file_system_id  = module.efs_model.file_system_id
  model_efs_access_point_id = module.efs_model.access_point_id
}

# --- Model loader: infra de soporte para el workflow "Populate Model EFS"
# (build+push de la imagen + run-task one-off que llena el model-efs) -----
module "model_loader" {
  source      = "./modules/model_loader"
  name        = local.prefix
  environment = var.environment

  model_efs_file_system_arn  = module.efs_model.file_system_arn
  model_efs_access_point_arn = module.efs_model.access_point_arn

  log_retention_days = var.log_retention_days
}

# ECR de la imagen de la app (lo creo a mano fuera de Terraform - se referencia
# aca solo para darle permiso de push al rol de GitHub Actions).
data "aws_ecr_repository" "app" {
  name = "source-trace-analysis-mngr"
}

# --- OIDC de GitHub Actions para los workflows del repo mngr -----------
#   Build & Deploy ECS  +  Populate Model EFS  (mismo secret AWS_DEPLOY_ROLE_ARN)
module "github_oidc" {
  source      = "./modules/github-oidc"
  name        = local.prefix
  environment = var.environment

  github_org            = var.github_org
  github_repo           = var.github_repo
  github_subject_filter = var.github_subject_filter
  github_owner_id       = var.github_owner_id
  github_repo_id        = var.github_repo_id

  ecr_repository_arns = [
    data.aws_ecr_repository.app.arn,
    module.model_loader.ecr_repository_arn,
  ]
  ecs_cluster_arn  = module.ecs.cluster_arn
  ecs_service_arns = [module.ecs.service_arn]
  pass_role_arns = [
    module.ecs.task_role_arn,
    module.ecs.execution_role_arn,
    module.model_loader.task_role_arn,
    module.model_loader.execution_role_arn,
  ]

  # Deploy via OIDC de los repos que no son el mngr (un rol por repo, scope a
  # push en main). Los repo_id salen del subject claim personalizado del owner.
  lambda_deploy_targets = {
    invoker = {
      github_repo    = "source_trace_invoker_function"
      github_repo_id = "1356504028"
      function_arn   = module.lambda.invoker_function_arn
    }
    response = {
      github_repo    = "source_trace_response_function"
      github_repo_id = "1358366035"
      function_arn   = module.lambda.results_function_arn
    }
  }

  frontend_deploy_targets = {
    web_ui = {
      github_repo                 = "source_trace_web_ui"
      github_repo_id              = "1356505963"
      bucket_arn                  = module.s3.web_ui_bucket_arn
      cloudfront_distribution_arn = module.cloudfront.web_ui_distribution_arn
    }
  }
}

# --- ECS analysis manager (Qwen) ---------------------------
module "ecs" {
  source      = "./modules/Ecs"
  name        = local.prefix
  environment = var.environment
  region      = var.region

  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.vpc.ecs_security_group_id

  container_image = var.model_container_image
  model_name      = var.model_name
  task_cpu        = var.ecs_task_cpu
  task_memory     = var.ecs_task_memory

  dynamodb_table_arn = module.dynamo.table_arn
  results_bucket_arn = module.s3.results_bucket_arn
  results_bucket_id  = module.s3.results_bucket_id
  upload_bucket_arn  = module.s3.upload_bucket_arn
  upload_bucket_id   = module.s3.upload_bucket_id

  repo_efs_file_system_id   = module.efs.file_system_id
  repo_efs_file_system_arn  = module.efs.file_system_arn
  repo_efs_access_point_id  = module.efs.access_point_id
  repo_efs_access_point_arn = module.efs.access_point_arn

  model_efs_file_system_id   = module.efs_model.file_system_id
  model_efs_file_system_arn  = module.efs_model.file_system_arn
  model_efs_access_point_id  = module.efs_model.access_point_id
  model_efs_access_point_arn = module.efs_model.access_point_arn

  log_retention_days = var.log_retention_days
}

# --- API Gateway ----------------------------------------------
#   Api_source_trace.json           -> SOURCE_TRACE_INVOKER_FUNCTION
#   Api_source_trace_response.json   -> SOURCE_TRACE_RESPONSE_FUNCTION
# (un archivo .tf por API dentro del modulo)
module "apigateway" {
  source      = "./modules/apigateway"
  name        = local.prefix
  environment = var.environment
  region      = var.region
  stage_name  = var.environment

  invoker_lambda_arn  = module.lambda.invoker_function_arn
  invoker_lambda_name = module.lambda.invoker_function_name

  response_lambda_arn  = module.lambda.results_function_arn
  response_lambda_name = module.lambda.results_function_name

  log_retention_days = var.log_retention_days
}

# --- Observabilidad -------------------------------------
module "cloudwatch" {
  source      = "./modules/cloudwatch"
  name        = local.prefix
  environment = var.environment
  region      = var.region
  alarm_email = var.alarm_email

  ecs_cluster_name = module.ecs.cluster_name

  state_machine_arn = module.stepfunction.state_machine_arn

  invoker_function_name = module.lambda.invoker_function_name
  results_function_name = module.lambda.results_function_name
}
