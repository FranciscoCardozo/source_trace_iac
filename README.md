# Source Trace IAC

Infraestructura Terraform del pipeline de análisis de código fuente de **Source Trace**.
Un usuario sube (o apunta a) un repo, un pipeline de 5 pasos en ECS Fargate lo
analiza usando un LLM (**Qwen3-8B**, GGUF, servido por `llama.cpp`), y el resultado
queda en DynamoDB + un bucket de artefactos.

- **Orquestación:** AWS Step Functions (Standard). **No hay SQS** — la state machine
  lanza cada paso como una task Fargate efímera (`ecs:runTask.sync`).
- **Inferencia:** un servicio ECS aparte (`qwen-inference`) con el modelo montado
  desde EFS. **On-demand:** lo prende el propio pipeline y lo apaga un Lambda por
  inactividad.
- **Estado entre pasos:** un EFS compartido (`repo-efs`) montado en todas las tasks.

---

## Arquitectura

```
                 Front (SPA)                          Usuario
              S3 web_ui  ──►  CloudFront (/app)  ──►  navegador
                                                        │
        ┌───────────────────────────────────────────────┼──────────────────────────────┐
        │  API invoker  (source_trace_api)              │   API response (source_trace_response_api)
        │  POST /V1/product/analysis/invoke             │   GET /V1/product/status/analysis
        │  GET  /V1/product/analysis/uploadUrl          │        │
        │        │                                      │        ▼
        │        ▼                                      │   Lambda results  ──►  DynamoDB + S3 results
        │  Lambda invoker                               │
        │    · firma URL de upload (S3)                 │
        │    · StartExecution({ jobId, payload })       │
        └────────┼─────────────────────────────────────────────────────────────────────┘
                 ▼
   Step Functions  "source_trace_analysis"   (timeout total 3 h)
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │ MarkRunning            DynamoDB  JOB#<jobId>/META  status = RUNNING              │
   │ EnsureModelUp          ecs:updateService  qwen-inference  desiredCount = 1       │
   │ WaitForModel ↔ CheckModel ↔ ModelReady   (poll hasta RunningCount ≥ 1)          │
   │ ModelWarmup            Wait 30 s  (llama.cpp cargando el modelo)                 │
   │ getSource ──► basicAnalysis ──► functionalResume ──► componentAnalysis ──►       │
   │                                                      arquitectureAnalysis        │
   │    cada paso:  ecs:runTask.sync  (Fargate, family source_trace_analysis_mngr)    │
   │      env override:  JOB_TYPE=<paso>  JOB_ID  SOURCE_TYPE  SOURCE_URL  ...         │
   │      monta repo-efs en /mnt/repo/<jobId>   (getSource escribe, el resto lee)     │
   │      habla con  http://qwen-inference.source-trace.local:3001  (HTTP)            │
   │      Retry: 3× errores transitorios de ECS · 1× States.TaskFailed                │
   │      Catch (States.ALL) ──► MarkFailed                                           │
   │ MarkSucceeded / MarkFailed ──► FailState    DynamoDB status final (+ error)      │
   └─────────────────────────────────────────────────────────────────────────────────┘

   qwen-inference   (ECS service · llama.cpp · modelo en model-efs /mnt/model · desiredCount 0↔1)
     ▲ scale-up   Step Functions  (estado EnsureModelUp)
     ▼ scale-down Lambda  source_trace_qwen_scale_down   (EventBridge cada 5 min:
                  si no hay ejecuciones RUNNING ni recientes < 10 min → desiredCount = 0)

   EFS
     repo-efs   fs-…549bec   /mnt/repo    read-write   estado compartido entre pasos
     model-efs  fs-…c80d10   /mnt/model   read-only    pesos del modelo (Qwen3-8B-UD-Q4_K_XL.gguf → model.gguf)
```

### El pipeline (5 pasos)

Cada paso es una task Fargate efímera de la familia `source_trace_analysis_mngr`
(la imagen y el resto del task definition los administra el repo de la app, no
Terraform — ver [El contenedor](#el-contenedor-analysis-mngr)). El Step Functions
usa siempre la **última revisión ACTIVE** de esa familia e inyecta por
`ContainerOverrides`:

| env | valor | origen |
|---|---|---|
| `JOB_TYPE` | `getSource` \| `basicAnalysis` \| `functionalResume` \| `componentAnalysis` \| `arquitectureAnalysis` | literal por estado |
| `JOB_ID` | id del job | `$.jobId` |
| `SOURCE_TYPE` | `GIT` \| `UPLOAD` | `$.payload.sourceType` |
| `SOURCE_URL` | URL del repo (GIT) | `$.payload.repoUrl` |
| `DYNAMODB_TABLE` | `source_trace_db` | literal |
| `PAYLOAD` | request completo serializado (JSON string) | `States.JsonToString($.payload)` |

El contenedor hace **ese** paso contra `/mnt/repo/$JOB_ID` y termina con
**exit 0** (éxito) o **≠ 0** (`States.TaskFailed` → Catch → job `FAILED`).

### Contrato de entrada (StartExecution)

```json
{ "jobId": "<uuid>", "payload": { "sourceType": "GIT", "repoUrl": "https://github.com/org/repo", ... } }
```

- `jobId` — string, obligatorio. Clave DynamoDB `PK = JOB#<jobId>`, `SK = META`,
  y directorio de trabajo `/mnt/repo/<jobId>`.
- `payload` — **objeto JSON** obligatorio. `getSource` lo parsea; el resto de los
  pasos leen lo que quedó en `/mnt/repo/<jobId>`.

---

## Módulos

| Módulo | Recursos |
|---|---|
| `modules/vpc` | VPC, 2 subredes públicas + 2 privadas, NAT gateway, VPC endpoint S3, SG de las tasks ECS (self-ref :3001 para hablar con qwen-inference) |
| `modules/s3` | Buckets `web_ui`, `results`, `upload` (privados, cifrados; upload con lifecycle de expiración) |
| `modules/cloudfront` | 2 distribuciones (web UI con `origin_path=/app`, results) + OAC + bucket policies |
| `modules/dynamo` | Tabla `source_trace_db` (`PK`/`SK`, PITR, TTL) |
| `modules/stepfunction` | State machine `source_trace_analysis` (5 pasos + EnsureModelUp/scale-up) + rol + log group |
| `modules/Ecs` | Cluster Fargate `source_trace_analysis_mngr`, task definition *bootstrap* (`ignore_changes=[container_definitions]`), roles exec/task, service en `desiredCount=0` |
| `modules/efs` | Filesystem + access point + mount targets + SG. Instanciado 2×: `repo-efs` y `model-efs` |
| `modules/lambda` | `source_trace_invoker_function` y `source_trace_results_function` (`nodejs20.x`; el código lo despliega el CI, `ignore_changes=[filename,source_code_hash]`) |
| `modules/apigateway` | 2 REST APIs definidas 100% por OpenAPI — un `.tf` por API: `source_trace_api.tf` (invoker) y `source_trace_response_api.tf` (response). `shared.tf` = rol CloudWatch + `aws_api_gateway_account` (global) |
| `modules/qwen_autoscaler` | Lambda `source_trace_qwen_scale_down` + regla EventBridge (apaga qwen-inference por inactividad) |
| `modules/model_loader` | ECR `source-trace-model-loader` + roles IAM para el workflow "Populate Model EFS" del repo de la app |
| `modules/manual_model_loader` | EC2 descartable para cargar el modelo a mano en `model-efs` (toggle `enable_manual_model_loader`, normalmente `false`) |
| `modules/github-oidc` | OIDC provider de GitHub + 1 rol de deploy por repo (app, 2 lambdas, frontend) |
| `modules/cloudwatch` | Dashboard `source_trace_analysis_mngr_metrics` + alarmas + SNS `source_trace_alarms` |

---

## Servicio de inferencia (`qwen-inference`)

- Imagen pública `ghcr.io/ggml-org/llama.cpp:server`, `-m /mnt/model/model.gguf --host 0.0.0.0 --port 3001 -c 4096 -t 4`.
- Descubrimiento por **AWS Cloud Map** (DNS privado `qwen-inference.source-trace.local:3001`),
  no Service Connect — las tasks del pipeline corren por `run-task` suelto y no
  pueden depender de un sidecar.
- **On-demand:** arranca en `desiredCount=0`.
  - **Prender:** el estado `EnsureModelUp` del Step Functions hace `updateService desiredCount=1`
    y espera (poll + warmup fijo) a que `llama.cpp` esté sirviendo.
  - **Apagar:** el Lambda `source_trace_qwen_scale_down` (EventBridge cada 5 min)
    pone `desiredCount=0` si no hay ejecuciones `RUNNING` ni una que haya
    terminado hace menos de `idle_minutes` (10). Maneja concurrencia: mientras
    haya algún job, se mantiene arriba.
- El task definition de `qwen-inference` **lo administra el repo de la app**
  (`ecs/qwen-inference-task-definition.json`), no Terraform.

> **Rendimiento:** un 8B Q4 en Fargate **sin GPU** corre a ~3–7 tok/s. Un pipeline
> completo puede tardar 30–90 min. Para tiempos razonables hace falta GPU
> (ECS/EC2 `g5`/`g6`, no Fargate) o un modelo más chico.

## El contenedor (`analysis-mngr`)

Terraform **solo aprovisiona infra** (cluster, roles, EFS, log group). El
contenedor y su task definition viven en el repo `FranciscoCardozo/source_trace_analysis_mngr`
y se despliegan por GitHub Actions (`register-task-definition`). El `task_role`
ya tiene: `dynamodb:*Item`/`Query` sobre `source_trace_db`, `s3:PutObject`
sobre `results`, `s3:GetObject` sobre `upload`, y `elasticfilesystem:ClientMount`/
`ClientWrite` sobre `repo-efs` (+ `ClientMount` sobre `model-efs`).

---

## APIs (definidas por OpenAPI)

Cada API se importa entera desde su OAS con
`aws_api_gateway_rest_api.body = templatefile(...)` + `put_rest_api_mode = "overwrite"`
(cada `apply` deja el API exactamente como el archivo; borrar un path del OAS lo
borra del API). El placeholder `${lambda_arn}` lo resuelve `templatefile()`.

| API | OAS | Lambda | Rutas |
|---|---|---|---|
| `source_trace_api` | `definitions/Api_source_trace.json` | `source_trace_invoker_function` | `POST /V1/product/analysis/invoke`, `GET /V1/product/analysis/uploadUrl` (+ `OPTIONS` CORS) |
| `source_trace_response_api` | `definitions/Api_source_trace_response.json` | `source_trace_results_function` | `GET /V1/product/status/analysis` (header `x-job-id`) (+ `OPTIONS` CORS) |

**CORS:** cada path tiene un `OPTIONS` con integración `MOCK` que devuelve los
headers. La integración `aws_proxy` no agrega headers CORS a la respuesta real —
**la Lambda debe devolver `Access-Control-Allow-Origin`**. Los headers custom
(`x-job-id`, `x-process`) están en `Access-Control-Allow-Headers`.

Los base URL:

```bash
terraform output api_invoke_url            # invoker
terraform output api_response_invoke_url   # response
```

---

## CI/CD (GitHub Actions vía OIDC)

`modules/github-oidc` crea un OIDC provider y **un rol de deploy por repo**
(least-privilege). Los repos usan un *subject claim* personalizado con IDs
numéricos: `repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>`.

| Repo | Rol (`secret AWS_DEPLOY_ROLE_ARN`) | Permite |
|---|---|---|
| `source_trace_analysis_mngr` | `source_trace_model_loader_deploy_role` | push a ECR (app + model-loader), `RegisterTaskDefinition`, `RunTask`, `UpdateService` |
| `source_trace_invoker_function` | `source_trace_invoker_lambda_deploy_role` | `lambda:UpdateFunctionCode` sobre esa función |
| `source_trace_response_function` | `source_trace_response_lambda_deploy_role` | idem |
| `source_trace_web_ui` | `source_trace_web_ui_frontend_deploy_role` | `s3 sync` al bucket web + `cloudfront:CreateInvalidation` |

Los roles de Lambda y frontend están scopeados a `ref:refs/heads/main`. Valores
para los secrets/vars:

```bash
terraform output github_actions_secret       # rol del repo mngr
terraform output github_actions_vars         # AWS_REGION, ECS_CLUSTER, ECR_REPOSITORY, ...
terraform output lambda_deploy_role_arns     # { invoker = "...", response = "..." }
terraform output frontend_deploy_role_arns   # { web_ui = "..." }
terraform output web_ui_bucket_name
terraform output web_ui_cloudfront_distribution_id
```

### Poblar el `model-efs`

El filesystem se crea vacío. Dos formas de cargar el `.gguf`:

1. **Workflow "Populate Model EFS"** del repo de la app (usa `model_loader`: ECR
   + roles + `run-task` one-off que baja el modelo de HuggingFace).
2. **EC2 auxiliar:** `terraform apply -var enable_manual_model_loader=true`,
   entrar con `terraform output manual_model_loader_ssm_command`, bajar el
   modelo a `/mnt/model`, `terraform apply -var enable_manual_model_loader=false`.

---

## Observabilidad y métricas

### Dashboard `source_trace_analysis_mngr_metrics`

```bash
terraform output cloudwatch_dashboard_url
```

| Sección | Widgets | Para qué |
|---|---|---|
| **ECS — inferencia (qwen)** | CPU/Memoria %, tasks deseadas vs corriendo | qué tan al límite está el 8B; confirma el on-demand (0 ↔ 1) |
| **ECS — pipeline (cluster)** | Memoria usada vs reservada (MiB), CPU usada vs reservada, **disco efímero usado vs reservado**, red Rx/Tx | `getSource` clona repos en los 20 GB de Fargate; picos de red = descargas |
| **Duración** | `ServiceIntegrationRunTime` (avg/max) = **cuánto dura cada task del pipeline**; `ExecutionTime` (avg/max) = ejecución completa; ejecuciones ok/fallidas/timeout | |
| **EFS** | `BurstCreditBalance`, `PermittedThroughput`, `PercentIOLimit`, `ClientConnections`, IO bytes read/write, `StorageBytes` | ambos EFS son *bursting*/*generalPurpose*: si los créditos llegan a 0 el throughput colapsa; `PercentIOLimit > 90` = throttling |
| **Lambdas** | invocaciones/errores (invoker, results, scale-down), duración | |

### Log groups

| | |
|---|---|
| `/aws/lambda/source_trace_invoker_function` · `/aws/lambda/source_trace_results_function` · `/aws/lambda/source_trace_qwen_scale_down` | Lambdas |
| `/ecs/source_trace_analysis_mngr` | tasks del pipeline (`JOB_TYPE`, `JOB_ID` en cada línea) |
| `/ecs/qwen-inference` | servidor de inferencia (`awslogs-create-group` activado) |
| `/aws/vendedlogs/states/source_trace_analysis` | ejecuciones del Step Functions (+ tracing X-Ray) |
| `/aws/apigateway/source_trace_api` · `/aws/apigateway/source_trace_response_api` | access logs de las APIs |

### Alarmas → SNS `source_trace_alarms` (`alarm_email` suscribe un email)

| Alarma | Métrica | Umbral |
|---|---|---|
| `source_trace_analysis_executions_failed` | `AWS/States ExecutionsFailed` | > 0 en 5 min |
| `source_trace_analysis_executions_timed_out` | `AWS/States ExecutionsTimedOut` | > 0 en 5 min |
| `source_trace_invoker_lambda_errors` / `..._results_lambda_errors` | `AWS/Lambda Errors` | > 0 en 5 min |
| `source_trace_repo_efs_io_throttling` | `AWS/EFS PercentIOLimit` (repo-efs) | > 90% por 15 min |
| `source_trace_model_efs_burst_credits_low` | `AWS/EFS BurstCreditBalance` (model-efs) | < ~500 GB (≈20% del máx) |

### Métricas útiles a futuro (aún no en el dashboard)

- **Métricas custom del `llama.cpp`** (tokens/s, cola de requests) — requieren que
  el contenedor las emita con `PutMetricData`; ahí se ve el rendimiento real de inferencia.
- Alarma de **costo** (`AWS/Billing EstimatedCharges`) por si el autoscaler deja
  `qwen-inference` prendido por un bug.
- `PercentIOLimit` en `model-efs` (hoy sólo en `repo-efs`).

---

## Uso

```bash
# credenciales y parámetros en terraform.tfvars (NO se commitea, está en .gitignore)
terraform init
terraform plan
terraform apply
```

Variables relevantes (`variables.tf`):

| Variable | Default | Nota |
|---|---|---|
| `model_service_name` | `qwen-inference-svc` | nombre del ECS service de inferencia (lo crea el CI con ese nombre) |
| `alarm_email` | `""` | email que recibe las alarmas (vacío = sin suscripción) |
| `enable_manual_model_loader` | `false` | enciende la EC2 auxiliar para cargar el modelo |
| `github_owner_id` / `github_repo_id` | `65205473` / `1356504872` | IDs numéricos del subject claim OIDC |
| `upload_allowed_origins` | `["*"]` | orígenes CORS del bucket de upload (restringir en prod) |
| `model_container_image` / `model_name` | placeholders | **vestigiales** — el task definition del `analysis-mngr` lo administra el CI |

> El módulo `stepfunction` tiene tunables: `pipeline_steps`, `model_warmup_seconds`
> (30), `execution_timeout_seconds` (10800), `step_timeout_seconds` (3600),
> `max_retries` (1).

---

## Notas

- **No hay SQS.** El diseño con `sqs:sendMessage.waitForTaskToken` fue reemplazado
  por el pipeline de 5 pasos con `ecs:runTask.sync`.
- El task definition y el código del `analysis-mngr` y de las Lambdas los
  administra el CI; Terraform los deja con `ignore_changes` y sólo aporta la
  revisión de arranque.
- `.github/workflows/db-migrate.yml` pertenece a la arquitectura vieja (RDS) y ya
  no se usa.
- Huérfanos de la arquitectura vieja, fuera de Terraform: bucket
  `s3-app-assessments`, CloudFront `E33I9IGNH1PVR6` / `E287DUH6V6EWA4`.
