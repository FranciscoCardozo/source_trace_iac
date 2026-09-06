// SOURCE_TRACE_RESPONSE_FUNCTION - placeholder de arranque.
//
// La logica real vive en el repo FranciscoCardozo/source_trace_response_function
// y se despliega por GitHub Actions. Terraform solo crea la funcion con este
// stub; ignore_changes deja que el CI sea el dueño del codigo.
//
// Responsabilidad: GET /V1/product/status/analysis -> DynamoDB + bucket de resultados.
exports.handler = async () => ({
  statusCode: 200,
  headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  body: JSON.stringify({ message: "source_trace_response_function bootstrap - pending CI deploy" }),
});
