# Source Trace IAC — Analysis Manager con Qwen en AWS

Infraestructura Terraform del pipeline de analisis que corre el modelo **Qwen**
sobre ECS Fargate.

## Arquitectura

```
usuario
  |
  v
SOURCE_TRACE_CLOUDFRONT ---------> S3  web_ui        (SPA estatica)
SOURCE_TRACE_RESULTS_CLOUDFRONT -> S3  results       (imagenes / artefactos)
  |
  v
SOURCE_TRACE_API (API Gateway REST, definido por OAS - ver mas abajo)
  |  ...rutas del OAS...  -> SOURCE_TRACE_INVOKER_FUNCTION / SOURCE_TRACE_RESULTS_FUNCTION
  |
  v
Step Functions "source_trace_analysis"  (Standard workflow)
  1. MarkRunning    -> DynamoDB status = RUNNING
  2. RunAnalysis    -> SQS INVOKER  (sendMessage .waitForTaskToken)
                         SOURCE_TRACE_ANALYSIS_MNGR (ECS Fargate, Qwen) consume
                         el mensaje, lee el codigo de  S3 upload, procesa y
                         responde con SendTaskSuccess/Failure
                         |-> DynamoDB  SOURCE_TRACE_DB
                         |-> S3        results
  3. MarkSucceeded / MarkFailed  -> DynamoDB status final (+ Retry / Catch / timeout)
```

El **Step Functions workflow** da control por ejecucion: reintentos con backoff,
`TimeoutSeconds` / `HeartbeatSeconds` sobre la tarea del ECS, y un estado final
garantizado (`SUCCEEDED` / `FAILED`) en DynamoDB aunque el worker se cuelgue.

Observabilidad:

- Un log group de CloudWatch por Lambda (`/aws/lambda/...`) y para el ECS (`/ecs/...`).
- Log group de acceso del API Gateway (`/aws/apigateway/...`).
- Log group de la state machine (`/aws/vendedlogs/states/...`) + tracing X-Ray.
- Dashboard **SOURCE_TRACE_ANALYSIS_MNGR_METRICS** con CPU/memoria/tareas del ECS,
  profundidad y edad de la cola SQS (incluida la DLQ), ejecuciones y duracion del
  Step Functions workflow, e invocaciones/errores/duracion de las Lambdas.
- Alarmas -> topic SNS `source_trace_alarms` (suscribe un email con `alarm_email`):
  CPU/memoria ECS, DLQ con mensajes, backlog de cola, errores de Lambda y
  ejecuciones FAILED del workflow.

## Modulos

| Modulo             | Recursos principales                                            |
|--------------------|----------------------------------------------------------------|
| `modules/vpc`      | VPC, 2 subredes publicas + 2 privadas, NAT, endpoint S3, SG ECS |
| `modules/s3`       | Buckets `web_ui`, `results` y `upload` (privados, cifrado, versionado) |
| `modules/cloudfront` | 2 distribuciones + OAC + bucket policies                      |
| `modules/sqs`      | Cola `invoker` + DLQ con redrive                                |
| `modules/dynamo`   | Tabla `source_trace_db` (PK/SK + GSI por estado, PITR, TTL)     |
| `modules/stepfunction` | Step Functions `source_trace_analysis` + rol + log group      |
| `modules/lambda`   | `invoker_function` (URL prefirmada de upload + StartExecution) y `results_function` |
| `modules/Ecs`      | Cluster Fargate, task def, service, autoscaling por cola SQS    |
| `modules/apigateway` | REST API **definido por OAS** (`definitions/Api_source_trace.json`), stage con access logs |
| `modules/cloudwatch` | Dashboard + alarmas + topic SNS                               |

## Uso

```bash
# credenciales y parametros en terraform.tfvars (NO se commitea)
terraform init
terraform plan
terraform apply
```

Variables relevantes (`variables.tf`):

- `model_container_image` — imagen del worker que hace long-polling de SQS y corre Qwen.
  Por ahora **sin GPU** (Fargate CPU); ajustar `ecs_task_cpu` / `ecs_task_memory`.
- `model_name` — id del modelo (default `Qwen/Qwen2.5-0.5B-Instruct`).
- `ecs_min_tasks` / `ecs_max_tasks` — `0` permite escala a cero cuando la cola esta vacia.
- `alarm_email` — email que recibe las alarmas (vacio = sin suscripcion).
- `upload_allowed_origins` — origenes CORS del bucket de upload (default `["*"]`, restringir al dominio del front en prod).
- `upload_expiration_days` — dias tras los que se borran los archivos subidos (default 30).

### SOURCE_TRACE_API se define por OAS

El REST API completo (paths, metodos, integraciones `aws_proxy` y el mock de
CORS por path) sale de [modules/apigateway/definitions/Api_source_trace.json](modules/apigateway/definitions/Api_source_trace.json),
importado con `aws_api_gateway_rest_api.body` + `put_rest_api_mode = "overwrite"`
(cada apply deja el API exactamente como dice el archivo — si se borra un path
del OAS, se borra del API tambien). Todas las rutas del archivo apuntan a una
sola Lambda via el placeholder `${lambda_arn}`, que Terraform resuelve con
`templatefile()` -> `SOURCE_TRACE_INVOKER_FUNCTION`.

**Los paths que trae el archivo hoy (`questionaire`, `assessments`, `sandbox`)
son los del proyecto anterior** — quedan como placeholder de referencia hasta
que se reemplacen por las rutas reales de Source Trace. La Lambda sandbox de
ese proyecto ya no existe; las rutas que la usaban se repuntaron a
`${lambda_arn}`. Para agregar una ruta: editar el JSON (nuevo `path` +
`x-amazon-apigateway-integration` apuntando a `${lambda_arn}`) y
`terraform apply` — no hace falta tocar ningun `.tf`. El permiso de invocacion
(`aws_lambda_permission`) ya cubre cualquier metodo/recurso del API.

`SOURCE_TRACE_RESULTS_FUNCTION` (el `GET` para consultar resultados) todavia
no tiene rutas en este OAS — va a vivir en un OAS/API propio mas adelante.

Para editar sin resolverlo a mano: `terraform console` -> `templatefile("modules/apigateway/definitions/Api_source_trace.json", {lambda_arn = "..."})`.

### Subida de codigo fuente (pendiente de reflejar en el OAS)

El flujo pensado, cuando el OAS tenga las rutas reales:

1. El front hace `POST /uploads` con `{ "filename": "...", "contentType": "..." }`.
2. La Lambda invoker devuelve `{ uploadUrl, bucket, key, expiresIn }` — `uploadUrl` es
   una URL prefirmada (`PUT`, TTL 15 min) contra `s3://<upload>/uploads/<uuid>/<filename>`.
3. El front hace `PUT` del archivo directo a `uploadUrl` (no pasa por la Lambda).
4. El front hace `POST /jobs` con `{ "key": "uploads/<uuid>/<filename>", ... }`.
5. El ECS lee `s3://$UPLOAD_BUCKET/<key>` (env var + `s3:GetObject` en el task role).

La logica ya esta en [src/invoker/index.py](modules/lambda/src/invoker/index.py) (rutea por
`event["resource"]`), solo falta que el OAS defina `/uploads` y `/jobs` apuntando
a `${lambda_arn}`.

El bucket `upload` es privado, con lifecycle que expira los objetos y aborta los
multipart incompletos. El `invoker` solo tiene `s3:PutObject` (para firmar); el
`task_role` del ECS tiene `s3:GetObject` / `s3:ListBucket`.

### El contenedor del ECS

Terraform solo aprovisiona la infra. El contenedor `analysis-mngr` debe:

1. Leer `SQS_QUEUE_URL`, `RESULTS_BUCKET`, `UPLOAD_BUCKET`, `MODEL_NAME`, `AWS_REGION` del entorno.
2. Hacer `ReceiveMessage` en la cola. Cada mensaje trae `{ jobId, payload, taskToken }`.
3. Leer el codigo de `s3://$UPLOAD_BUCKET/<payload.key>`, procesar con Qwen y subir
   los artefactos a `s3://$RESULTS_BUCKET/<jobId>/...`.
4. Reportar el resultado a Step Functions con `SendTaskSuccess` (o `SendTaskFailure`)
   usando el `taskToken`; para trabajos largos, `SendTaskHeartbeat` periodico.
5. `DeleteMessage` al terminar.

Los estados `RUNNING` / `SUCCEEDED` / `FAILED` en DynamoDB los escribe la state
machine; el worker solo escribe los artefactos y (opcionalmente) datos de negocio.
El `task_role` ya tiene permisos de SQS, DynamoDB, S3 y `states:SendTask*`.

## Notas

- La arquitectura vieja (EC2, RDS, API Gateway "assessments", 1 CloudFront) ya fue
  reemplazada por esta. Quedaron huerfanos, fuera de Terraform: el bucket
  `s3-app-assessments` y las distribuciones CloudFront `E33I9IGNH1PVR6` /
  `E287DUH6V6EWA4` (borrar a mano si se quiere).
- `.github/workflows/db-migrate.yml` pertenece a la arquitectura vieja (RDS) y
  ya no se usa. El OAS viejo (`Api_Assesstments.json`) se movio y paso a ser
  [modules/apigateway/definitions/Api_source_trace.json](modules/apigateway/definitions/Api_source_trace.json).
