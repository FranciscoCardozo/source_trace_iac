// SOURCE_TRACE_INVOKER_FUNCTION - placeholder de arranque.
//
// La logica real vive en el repo FranciscoCardozo/source_trace_invoker_function
// y se despliega por GitHub Actions (aws lambda update-function-code). Terraform
// solo crea la funcion con este stub; ignore_changes deja que el CI sea el
// dueño del codigo.
//
// Responsabilidades: POST /uploads -> URL prefirmada; POST /jobs -> StartExecution.
exports.handler = async () => ({
  statusCode: 200,
  headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  body: JSON.stringify({ message: "source_trace_invoker_function bootstrap - pending CI deploy" }),
});
