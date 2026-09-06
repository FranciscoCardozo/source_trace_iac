# --- CDN -------------------------------------------------------
output "web_ui_cloudfront_domain" {
  description = "Dominio de SOURCE_TRACE_CLOUDFRONT (web UI)"
  value       = module.cloudfront.web_ui_domain_name
}

output "results_cloudfront_domain" {
  description = "Dominio de SOURCE_TRACE_RESULTS_CLOUDFRONT (imagenes de resultados)"
  value       = module.cloudfront.results_domain_name
}

# --- Buckets -------------------------------------------------
output "web_ui_bucket" {
  value = module.s3.web_ui_bucket_id
}

output "results_bucket" {
  value = module.s3.results_bucket_id
}

output "upload_bucket" {
  description = "Bucket donde el front sube el codigo fuente (via URL prefirmada de la Lambda invoker)"
  value       = module.s3.upload_bucket_id
}

# --- API ----------------------------------------------------
output "api_invoke_url" {
  description = "Base URL del API invoker (dispara el analisis -> SOURCE_TRACE_INVOKER_FUNCTION)"
  value       = module.apigateway.invoker_invoke_url
}

output "api_response_invoke_url" {
  description = "Base URL del API response (GET /V1/product/status/analysis -> SOURCE_TRACE_RESPONSE_FUNCTION)"
  value       = module.apigateway.response_invoke_url
}

# --- Orquestacion -----------------------------------------
output "analysis_state_machine_arn" {
  description = "Step Functions workflow que orquesta cada analisis"
  value       = module.stepfunction.state_machine_arn
}

output "analysis_state_machine_name" {
  value = module.stepfunction.state_machine_name
}

# --- DynamoDB ----------------------------------------------
output "dynamodb_table_name" {
  value = module.dynamo.table_name
}

# --- EFS repo-efs (lectura-escritura, compartido entre pasos del pipeline)
output "repo_efs_file_system_id" {
  description = "Para reemplazar <REPO_EFS_FILE_SYSTEM_ID> en ecs/task-definition.json"
  value       = module.efs.file_system_id
}

output "repo_efs_access_point_id" {
  description = "Para reemplazar <REPO_EFS_ACCESS_POINT_ID_READWRITE> en ecs/task-definition.json"
  value       = module.efs.access_point_id
}

# --- EFS model-efs (solo lectura, pesos del modelo Qwen) ----------------
output "model_efs_file_system_id" {
  description = "Para reemplazar <EFS_FILE_SYSTEM_ID> en ecs/task-definition.json"
  value       = module.efs_model.file_system_id
}

output "model_efs_access_point_id" {
  description = "Para reemplazar <EFS_ACCESS_POINT_ID_READONLY> en ecs/task-definition.json"
  value       = module.efs_model.access_point_id
}

# --- GitHub Actions (repo mngr): Settings > Secrets and variables > Actions
output "github_actions_secret" {
  description = "Secret AWS_DEPLOY_ROLE_ARN (mismo para los dos workflows)"
  value       = module.github_oidc.role_arn
}

# --- GitHub Actions (repos de las Lambdas): secret AWS_DEPLOY_ROLE_ARN por repo
output "lambda_deploy_role_arns" {
  description = "secret AWS_DEPLOY_ROLE_ARN de cada repo de Lambda (invoker / response)"
  value       = module.github_oidc.lambda_deploy_role_arns
}

# --- GitHub Actions (repo del frontend): secret AWS_DEPLOY_ROLE_ARN
output "frontend_deploy_role_arns" {
  description = "secret AWS_DEPLOY_ROLE_ARN del repo de frontend (web_ui)"
  value       = module.github_oidc.frontend_deploy_role_arns
}

output "web_ui_bucket_name" {
  description = "secret AWS_S3_BUCKET del workflow de frontend"
  value       = module.s3.web_ui_bucket_id
}

output "web_ui_cloudfront_distribution_id" {
  description = "secret AWS_CLOUDFRONT_DISTRIBUTION_ID del workflow de frontend"
  value       = module.cloudfront.web_ui_distribution_id
}

output "github_actions_vars" {
  description = "Repository variables para los workflows del repo mngr"
  value = {
    # comunes
    AWS_REGION          = var.region
    ECS_CLUSTER         = module.ecs.cluster_name
    ECS_SUBNETS         = join(",", module.vpc.private_subnet_ids)
    ECS_SECURITY_GROUPS = module.vpc.ecs_security_group_id

    # Build & Deploy ECS
    ECR_REPOSITORY = data.aws_ecr_repository.app.name
    ECS_SERVICE    = module.ecs.service_name
    CONTAINER_NAME = var.app_container_name

    # Populate Model EFS
    MODEL_LOADER_ECR_REPOSITORY = module.model_loader.ecr_repository_name
    MODEL_LOADER_CONTAINER_NAME = var.model_loader_container_name
  }
}

output "repo_efs_security_group_id" {
  value = module.efs.security_group_id
}

# --- EC2 auxiliar de carga del modelo (solo si enable_manual_model_loader = true)
output "manual_model_loader_ssm_command" {
  description = "Session Manager a la EC2 auxiliar para cargar el modelo"
  value       = module.manual_model_loader.ssm_command
}

output "manual_model_loader_download_hint" {
  description = "Comando de descarga a correr dentro de la EC2 auxiliar"
  value       = module.manual_model_loader.download_hint
}

# --- ECS --------------------------------------------------
output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "ecs_log_group" {
  value = module.ecs.log_group_name
}

# --- Observabilidad -------------------------------------
output "cloudwatch_dashboard_url" {
  description = "SOURCE_TRACE_ANALYSIS_MNGR_METRICS"
  value       = module.cloudwatch.dashboard_url
}

output "alarms_sns_topic_arn" {
  value = module.cloudwatch.alarms_topic_arn
}

output "lambda_log_groups" {
  value = {
    invoker = module.lambda.invoker_log_group_name
    results = module.lambda.results_log_group_name
  }
}
