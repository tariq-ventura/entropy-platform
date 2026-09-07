#!/usr/bin/env bash
set -euo pipefail

# Prueba end-to-end de fleet-service + logistic-service + entropy-mcp-server.
#
# Requisitos:
#   - curl
#   - jq
#   - fleet-service ejecutándose
#   - logistic-service ejecutándose y configurado para consultar fleet-service
#   - entropy-mcp-server ejecutándose y configurado para consultar logistic-service
#
# Uso local:
#   chmod +x fleet-logistic-e2e-test.sh
#   ./fleet-logistic-e2e-test.sh
#
# URLs personalizadas:
#   FLEET_BASE_URL=http://localhost:3000/api/v1 \
#   LOGISTIC_BASE_URL=http://localhost:3001/api/v1 \
#   MCP_BASE_URL=http://localhost:3002 \
#   MCP_API_KEY=entropy-local-secret \
#   ./fleet-logistic-e2e-test.sh

FLEET_BASE_URL="${FLEET_BASE_URL:-http://localhost:3000/api/v1}"
LOGISTIC_BASE_URL="${LOGISTIC_BASE_URL:-http://localhost:3001/api/v1}"
MCP_BASE_URL="${MCP_BASE_URL:-http://localhost:3002}"
MCP_ENDPOINT="${MCP_BASE_URL%/}/mcp"
MCP_API_KEY="${MCP_API_KEY:-entropy-local-secret}"
MCP_PROTOCOL_VERSION="${MCP_PROTOCOL_VERSION:-2026-07-28}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-5}"
CURL_MAX_TIME="${CURL_MAX_TIME:-30}"
RUN_ID="${RUN_ID:-$(date +%s)}"
BODY_FILE="$(mktemp)"

HTTP_STATUS=""
FLEET_ID=""
NEAR_EQUIPMENT_ID=""
FAR_EQUIPMENT_ID=""
REQUEST_ID=""
SECOND_REQUEST_ID=""
ASSIGNMENT_ID=""
CANCEL_ASSIGNMENT_ID=""

cleanup() {
  rm -f "${BODY_FILE}"
}

trap cleanup EXIT

for dependency in curl jq; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "ERROR: se requiere ${dependency}" >&2
    exit 1
  fi
done

print_body() {
  if [[ -s "${BODY_FILE}" ]]; then
    jq . "${BODY_FILE}" 2>/dev/null || sed -n '1,160p' "${BODY_FILE}"
  fi
}

fail() {
  local message="$1"

  echo "FAIL: ${message}" >&2
  print_body
  exit 1
}

pass() {
  echo "PASS: $1"
}

call_api() {
  local service="$1"
  local method="$2"
  local path="$3"
  local expected_codes="$4"
  local payload="${5:-}"
  local base_url

  case "${service}" in
    fleet)
      base_url="${FLEET_BASE_URL}"
      ;;
    logistic)
      base_url="${LOGISTIC_BASE_URL}"
      ;;
    *)
      echo "Servicio desconocido: ${service}" >&2
      exit 1
      ;;
  esac

  echo
  echo "[${service}] ${method} ${path}"

  if [[ -n "${payload}" ]]; then
    HTTP_STATUS="$(curl --silent --show-error \
      --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
      --max-time "${CURL_MAX_TIME}" \
      --output "${BODY_FILE}" \
      --write-out '%{http_code}' \
      --request "${method}" \
      --header 'Content-Type: application/json' \
      --data "${payload}" \
      "${base_url}${path}")"
  else
    HTTP_STATUS="$(curl --silent --show-error \
      --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
      --max-time "${CURL_MAX_TIME}" \
      --output "${BODY_FILE}" \
      --write-out '%{http_code}' \
      --request "${method}" \
      "${base_url}${path}")"
  fi

  echo "HTTP ${HTTP_STATUS}"
  print_body

  if [[ " ${expected_codes} " != *" ${HTTP_STATUS} "* ]]; then
    echo "Se esperaba uno de estos códigos: ${expected_codes}" >&2
    exit 1
  fi
}

call_http() {
  local label="$1"
  local method="$2"
  local url="$3"
  local expected_codes="$4"

  echo
  echo "[${label}] ${method} ${url}"

  HTTP_STATUS="$(curl --silent --show-error \
    --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
    --max-time "${CURL_MAX_TIME}" \
    --output "${BODY_FILE}" \
    --write-out '%{http_code}' \
    --request "${method}" \
    "${url}")"

  echo "HTTP ${HTTP_STATUS}"
  print_body

  if [[ " ${expected_codes} " != *" ${HTTP_STATUS} "* ]]; then
    echo "Se esperaba uno de estos códigos: ${expected_codes}" >&2
    exit 1
  fi
}

build_mcp_body() {
  local request_id="$1"
  local method="$2"
  local params="$3"

  jq -cn \
    --arg request_id "${request_id}" \
    --arg method "${method}" \
    --arg protocol_version "${MCP_PROTOCOL_VERSION}" \
    --argjson params "${params}" \
    '{
      jsonrpc: "2.0",
      id: $request_id,
      method: $method,
      params: ($params + {
        _meta: {
          "io.modelcontextprotocol/protocolVersion": $protocol_version,
          "io.modelcontextprotocol/clientInfo": {
            name: "entropy-e2e-test",
            version: "1.0.0"
          },
          "io.modelcontextprotocol/clientCapabilities": {}
        }
      })
    }'
}

call_mcp() {
  local method="$1"
  local request_id="$2"
  local params="$3"
  local expected_codes="$4"
  local tool_name="${5:-}"
  local payload
  local -a headers

  payload="$(build_mcp_body "${request_id}" "${method}" "${params}")"
  headers=(
    --header "Authorization: Bearer ${MCP_API_KEY}"
    --header 'Content-Type: application/json'
    --header 'Accept: application/json, text/event-stream'
    --header "MCP-Protocol-Version: ${MCP_PROTOCOL_VERSION}"
    --header "Mcp-Method: ${method}"
  )

  if [[ -n "${tool_name}" ]]; then
    headers+=(--header "Mcp-Name: ${tool_name}")
  fi

  echo
  if [[ -n "${tool_name}" ]]; then
    echo "[mcp] ${method} ${tool_name}"
  else
    echo "[mcp] ${method}"
  fi

  HTTP_STATUS="$(curl --silent --show-error \
    --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
    --max-time "${CURL_MAX_TIME}" \
    --output "${BODY_FILE}" \
    --write-out '%{http_code}' \
    --request POST \
    "${headers[@]}" \
    --data "${payload}" \
    "${MCP_ENDPOINT}")"

  echo "HTTP ${HTTP_STATUS}"
  print_body

  if [[ " ${expected_codes} " != *" ${HTTP_STATUS} "* ]]; then
    echo "Se esperaba uno de estos códigos: ${expected_codes}" >&2
    exit 1
  fi
}

call_mcp_without_auth() {
  local payload

  payload="$(build_mcp_body \
    "mcp-auth-${RUN_ID}" \
    "tools/list" \
    '{}')"

  echo
  echo "[mcp] POST sin autenticación"

  HTTP_STATUS="$(curl --silent --show-error \
    --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
    --max-time "${CURL_MAX_TIME}" \
    --output "${BODY_FILE}" \
    --write-out '%{http_code}' \
    --request POST \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json, text/event-stream' \
    --header "MCP-Protocol-Version: ${MCP_PROTOCOL_VERSION}" \
    --header 'Mcp-Method: tools/list' \
    --data "${payload}" \
    "${MCP_ENDPOINT}")"

  echo "HTTP ${HTTP_STATUS}"
  print_body

  if [[ "${HTTP_STATUS}" != "401" ]]; then
    fail "MCP debe rechazar peticiones sin autenticación"
  fi

  pass "MCP rechaza peticiones sin autenticación"
}

call_mcp_tool() {
  local tool_name="$1"
  local arguments="$2"
  local request_id="${3:-mcp-tool-${RUN_ID}}"

  call_mcp \
    "tools/call" \
    "${request_id}" \
    "$(jq -cn \
      --arg tool_name "${tool_name}" \
      --argjson arguments "${arguments}" \
      '{name: $tool_name, arguments: $arguments}')" \
    "200" \
    "${tool_name}"
}

assert_mcp_success() {
  local message="$1"

  assert_json \
    '.error == null and (.result.isError // false) == false' \
    "${message}"
}

assert_mcp_tool_error() {
  local message="$1"

  assert_json \
    '.error == null and .result.isError == true' \
    "${message}"
}

assert_mcp_contains() {
  local expected_value="$1"
  local message="$2"

  if ! jq -e \
    --arg expected_value "${expected_value}" \
    '[.. | strings | select(contains($expected_value))] | length > 0' \
    "${BODY_FILE}" >/dev/null; then
    fail "${message}"
  fi

  pass "${message}"
}

assert_json() {
  local expression="$1"
  local message="$2"

  if ! jq -e "${expression}" "${BODY_FILE}" >/dev/null; then
    fail "${message}"
  fi

  pass "${message}"
}

extract_id() {
  jq -er '.data.id // .id // empty' "${BODY_FILE}"
}

assert_valid_id() {
  local id="$1"
  local resource="$2"

  if [[ -z "${id}" ]]; then
    fail "${resource} no devolvió un ID"
  fi

  if [[ "${id}" == "00000000-0000-0000-0000-000000000000" ]]; then
    fail "${resource} devolvió uuid.Nil"
  fi
}

echo "Fleet API:    ${FLEET_BASE_URL}"
echo "Logistic API: ${LOGISTIC_BASE_URL}"
echo "MCP endpoint: ${MCP_ENDPOINT}"
echo "RUN_ID:       ${RUN_ID}"

# 1. Comprobar que los tres servicios responden.
call_api fleet GET "/equipments?page=1&pageSize=1" "200"
pass "fleet-service está disponible"

call_api logistic GET "/requests?page=1&pageSize=1" "200"
pass "logistic-service está disponible"

call_http mcp GET "${MCP_BASE_URL%/}/health" "200"
pass "entropy-mcp-server está disponible"

# 2. Validar autenticación, descubrimiento y catálogo de herramientas MCP.
call_mcp_without_auth

call_mcp \
  "server/discover" \
  "mcp-discover-${RUN_ID}" \
  '{}' \
  "200"
assert_json \
  '.error == null and (.result.capabilities.tools | type) == "object"' \
  "MCP anuncia soporte para tools"

call_mcp \
  "tools/list" \
  "mcp-tools-${RUN_ID}" \
  '{}' \
  "200"
assert_json \
  '([
    "create_logistics_request",
    "get_logistics_request",
    "get_recommendations",
    "create_assignment",
    "get_assignment",
    "complete_assignment",
    "cancel_assignment"
  ] - [.result.tools[].name]) | length == 0' \
  "MCP expone todas las herramientas logísticas esperadas"

# 3. Crear una flota.
FLEET_PAYLOAD="$(jq -n \
  --arg code "FLEET-E2E-${RUN_ID}" \
  --arg name "Flota E2E ${RUN_ID}" \
  '{code: $code, name: $name}')"

call_api fleet POST "/fleets" "201" "${FLEET_PAYLOAD}"
FLEET_ID="$(extract_id)"
assert_valid_id "${FLEET_ID}" "La flota"
pass "flota creada: ${FLEET_ID}"

# 4. Crear una excavadora cercana, con buen margen de mantenimiento.
NEAR_EQUIPMENT_PAYLOAD="$(jq -n \
  --arg code "EXC-NEAR-${RUN_ID}" \
  --arg serial "SERIAL-NEAR-${RUN_ID}" \
  '{
    code: $code,
    type: "EXCAVATOR",
    brand: "Caterpillar",
    model: "320",
    serialNumber: $serial,
    year: 2026,
    capacityTons: 23,
    location: {
      name: "San Miguel",
      latitude: 13.4835,
      longitude: -88.1828
    },
    engineHours: 100,
    maintenanceIntervalHours: 500,
    fuelPercent: 95
  }')"

call_api fleet POST "/equipments" "201" "${NEAR_EQUIPMENT_PAYLOAD}"
NEAR_EQUIPMENT_ID="$(extract_id)"
assert_valid_id "${NEAR_EQUIPMENT_ID}" "La maquinaria cercana"
pass "maquinaria cercana creada: ${NEAR_EQUIPMENT_ID}"

# 5. Crear otra excavadora más distante y con menor margen.
FAR_EQUIPMENT_PAYLOAD="$(jq -n \
  --arg code "EXC-FAR-${RUN_ID}" \
  --arg serial "SERIAL-FAR-${RUN_ID}" \
  '{
    code: $code,
    type: "EXCAVATOR",
    brand: "John Deere",
    model: "210G",
    serialNumber: $serial,
    year: 2025,
    capacityTons: 22,
    location: {
      name: "Santa Ana",
      latitude: 13.9942,
      longitude: -89.5597
    },
    engineHours: 300,
    maintenanceIntervalHours: 100,
    fuelPercent: 60
  }')"

call_api fleet POST "/equipments" "201" "${FAR_EQUIPMENT_PAYLOAD}"
FAR_EQUIPMENT_ID="$(extract_id)"
assert_valid_id "${FAR_EQUIPMENT_ID}" "La maquinaria distante"
pass "maquinaria distante creada: ${FAR_EQUIPMENT_ID}"

# 6. Agregar ambas maquinarias a la flota.
call_api fleet PUT "/fleets/${FLEET_ID}/equipments/${NEAR_EQUIPMENT_ID}" "200"
call_api fleet PUT "/fleets/${FLEET_ID}/equipments/${FAR_EQUIPMENT_ID}" "200"

call_api fleet GET "/fleets/${FLEET_ID}/equipments" "200"
assert_json \
  "[.. | objects | .id? | select(. == \"${NEAR_EQUIPMENT_ID}\")] | length > 0" \
  "la flota contiene la maquinaria cercana"
assert_json \
  "[.. | objects | .id? | select(. == \"${FAR_EQUIPMENT_ID}\")] | length > 0" \
  "la flota contiene la maquinaria distante"

# 7. Crear una solicitud logística PENDING en San Miguel mediante MCP.
PROJECT_NAME="Proyecto integrado ${RUN_ID}"
REQUEST_PAYLOAD="$(jq -n \
  --arg project_name "${PROJECT_NAME}" \
  '{
    equipmentType: "EXCAVATOR",
    projectName: $project_name,
    location: {
      name: "San Miguel",
      latitude: 13.4833,
      longitude: -88.1833
    },
    startDate: "2030-09-10T08:00:00Z",
    endDate: "2030-09-15T18:00:00Z"
  }')"

call_mcp_tool \
  "create_logistics_request" \
  "${REQUEST_PAYLOAD}" \
  "mcp-create-request-${RUN_ID}"
assert_mcp_success "MCP crea la solicitud logística"
assert_mcp_contains \
  "${PROJECT_NAME}" \
  "la respuesta MCP contiene el proyecto creado"

# Se obtiene el ID desde Logistics para validar también la persistencia real.
call_api logistic GET "/requests?page=1&pageSize=100" "200"
REQUEST_ID="$(jq -r \
  --arg project_name "${PROJECT_NAME}" \
  '[.data[] | select(.projectName == $project_name)] | first | .id // empty' \
  "${BODY_FILE}")"
assert_valid_id "${REQUEST_ID}" "La solicitud logística"

call_api logistic GET "/requests/${REQUEST_ID}" "200"
assert_json '(.data.status // .status) == "PENDING"' \
  "la solicitud inicia en PENDING"
pass "solicitud creada: ${REQUEST_ID}"

# 8. Consultar la solicitud y sus recomendaciones mediante MCP.
call_mcp_tool \
  "get_logistics_request" \
  "$(jq -cn --arg request_id "${REQUEST_ID}" '{requestId: $request_id}')" \
  "mcp-get-request-${RUN_ID}"
assert_mcp_success "MCP consulta una solicitud logística"
assert_mcp_contains \
  "${REQUEST_ID}" \
  "la respuesta MCP contiene el request solicitado"

call_mcp_tool \
  "get_recommendations" \
  "$(jq -cn --arg request_id "${REQUEST_ID}" '{requestId: $request_id}')" \
  "mcp-recommendations-${RUN_ID}"
assert_mcp_success "MCP obtiene recomendaciones"
assert_mcp_contains \
  "${NEAR_EQUIPMENT_ID}" \
  "MCP devuelve la maquinaria cercana recomendada"
assert_mcp_contains \
  "${FAR_EQUIPMENT_ID}" \
  "MCP devuelve la maquinaria distante recomendada"

UNKNOWN_REQUEST_ID="11111111-1111-4111-8111-111111111111"
call_mcp_tool \
  "get_logistics_request" \
  "$(jq -cn --arg request_id "${UNKNOWN_REQUEST_ID}" '{requestId: $request_id}')" \
  "mcp-request-not-found-${RUN_ID}"
assert_mcp_tool_error \
  "MCP representa un request inexistente como error de ejecución de tool"

# 9. Logistics consulta Fleet y genera las recomendaciones por REST.
call_api logistic GET "/requests/${REQUEST_ID}/recommendations" "200"

assert_json \
  ".data.requestId == \"${REQUEST_ID}\"" \
  "la recomendación corresponde a la solicitud"
assert_json \
  ".data.recommendations | any(.equipmentId == \"${NEAR_EQUIPMENT_ID}\")" \
  "la maquinaria cercana aparece en las recomendaciones"
assert_json \
  ".data.recommendations | any(.equipmentId == \"${FAR_EQUIPMENT_ID}\")" \
  "la maquinaria distante aparece en las recomendaciones"

NEAR_SCORE="$(jq -er \
  --arg id "${NEAR_EQUIPMENT_ID}" \
  '.data.recommendations[] | select(.equipmentId == $id) | .score' \
  "${BODY_FILE}")"

FAR_SCORE="$(jq -er \
  --arg id "${FAR_EQUIPMENT_ID}" \
  '.data.recommendations[] | select(.equipmentId == $id) | .score' \
  "${BODY_FILE}")"

if ! jq -en \
  --argjson near "${NEAR_SCORE}" \
  --argjson far "${FAR_SCORE}" \
  '$near > $far' >/dev/null; then
  fail "la maquinaria cercana debería tener mayor score"
fi

pass "ranking correcto: ${NEAR_SCORE} > ${FAR_SCORE}"

# 10. Crear la asignación mediante MCP con el equipo mejor recomendado.
# Primero se comprueba que MCP no ejecute la mutación sin confirmación humana.
CREATE_ASSIGNMENT_PAYLOAD="$(jq -n \
  --arg equipment_id "${NEAR_EQUIPMENT_ID}" \
  '{
    equipmentId: $equipment_id,
    reason: "Maquinaria seleccionada de las recomendaciones"
  }')"

MCP_ASSIGNMENT_WITHOUT_CONFIRMATION="$(jq -cn \
  --arg request_id "${REQUEST_ID}" \
  --arg equipment_id "${NEAR_EQUIPMENT_ID}" \
  '{
    requestId: $request_id,
    equipmentId: $equipment_id,
    reason: "Prueba MCP sin confirmación",
    confirmed: false
  }')"

call_mcp_tool \
  "create_assignment" \
  "${MCP_ASSIGNMENT_WITHOUT_CONFIRMATION}" \
  "mcp-assignment-unconfirmed-${RUN_ID}"
assert_mcp_tool_error \
  "MCP rechaza crear una asignación sin confirmed=true"

call_api logistic GET "/requests/${REQUEST_ID}/assignment" "404"
pass "la llamada MCP sin confirmación no creó una asignación"

MCP_ASSIGNMENT_CONFIRMED="$(jq -cn \
  --arg request_id "${REQUEST_ID}" \
  --arg equipment_id "${NEAR_EQUIPMENT_ID}" \
  '{
    requestId: $request_id,
    equipmentId: $equipment_id,
    reason: "Maquinaria seleccionada de las recomendaciones",
    confirmed: true
  }')"

call_mcp_tool \
  "create_assignment" \
  "${MCP_ASSIGNMENT_CONFIRMED}" \
  "mcp-assignment-confirmed-${RUN_ID}"
assert_mcp_success "MCP crea la asignación confirmada"
assert_mcp_contains \
  "${REQUEST_ID}" \
  "la respuesta MCP contiene el request asignado"
assert_mcp_contains \
  "${NEAR_EQUIPMENT_ID}" \
  "la respuesta MCP contiene el equipo asignado"

call_api logistic GET "/requests/${REQUEST_ID}/assignment" "200"
ASSIGNMENT_ID="$(extract_id)"
assert_valid_id "${ASSIGNMENT_ID}" "La asignación"
assert_json ".data.requestId == \"${REQUEST_ID}\"" \
  "la asignación pertenece al request"
assert_json ".data.equipmentId == \"${NEAR_EQUIPMENT_ID}\"" \
  "la asignación utiliza el equipo recomendado"
assert_json '.data.status == "ACTIVE"' \
  "la asignación inicia en ACTIVE"

# 11. Verificar los efectos de la creación en ambos microservicios.
call_api logistic GET "/requests/${REQUEST_ID}" "200"
assert_json '(.data.status // .status) == "ASSIGNED"' \
  "crear Assignment cambia el request a ASSIGNED"

call_api fleet GET "/equipments/${NEAR_EQUIPMENT_ID}" "200"
assert_json '(.data.status // .status) == "RESERVED"' \
  "crear Assignment reserva la maquinaria en Fleet"

call_api logistic GET "/requests/${REQUEST_ID}/assignment" "200"
assert_json ".data.id == \"${ASSIGNMENT_ID}\"" \
  "consultar Assignment por request devuelve el registro correcto"

call_mcp_tool \
  "get_assignment" \
  "$(jq -cn --arg request_id "${REQUEST_ID}" '{requestId: $request_id}')" \
  "mcp-get-assignment-${RUN_ID}"
assert_mcp_success "MCP consulta la asignación por request"
assert_mcp_contains \
  "${ASSIGNMENT_ID}" \
  "la respuesta MCP contiene la asignación correcta"

call_api logistic GET "/assignments?status=ACTIVE&page=1&pageSize=100" "200"
assert_json \
  ".data | any(.id == \"${ASSIGNMENT_ID}\" and .status == \"ACTIVE\")" \
  "la asignación aparece en el listado de activas"

# 12. Un request ASSIGNED no acepta recomendaciones ni otra asignación.
call_api logistic GET "/requests/${REQUEST_ID}/recommendations" "409"
pass "una solicitud ASSIGNED no genera nuevas recomendaciones"

call_api logistic POST \
  "/requests/${REQUEST_ID}/assignment" \
  "409" \
  "${CREATE_ASSIGNMENT_PAYLOAD}"
pass "un request no puede recibir dos asignaciones"

# 13. Crear otro request para comprobar que RESERVED desaparece del inventario.
SECOND_REQUEST_PAYLOAD="$(jq -n \
  --arg project_name "Proyecto cancelable ${RUN_ID}" \
  '{
    equipmentType: "EXCAVATOR",
    projectName: $project_name,
    location: {
      name: "San Miguel",
      latitude: 13.4833,
      longitude: -88.1833
    },
    startDate: "2030-10-01T08:00:00Z",
    endDate: "2030-10-05T18:00:00Z"
  }')"

call_api logistic POST "/requests" "201" "${SECOND_REQUEST_PAYLOAD}"
SECOND_REQUEST_ID="$(extract_id)"
assert_valid_id "${SECOND_REQUEST_ID}" "El segundo request"

call_api logistic GET \
  "/requests/${SECOND_REQUEST_ID}/recommendations" \
  "200"

assert_json \
  ".data.recommendations | all(.equipmentId != \"${NEAR_EQUIPMENT_ID}\")" \
  "la maquinaria RESERVED no aparece en otro request"
assert_json \
  ".data.recommendations | any(.equipmentId == \"${FAR_EQUIPMENT_ID}\")" \
  "la maquinaria AVAILABLE continúa siendo recomendada"

# 14. El equipo reservado no puede asignarse a otro request.
RESERVED_ASSIGNMENT_PAYLOAD="$(jq -n \
  --arg equipment_id "${NEAR_EQUIPMENT_ID}" \
  '{
    equipmentId: $equipment_id,
    reason: "Intento de asignación duplicada"
  }')"

call_api logistic POST \
  "/requests/${SECOND_REQUEST_ID}/assignment" \
  "409" \
  "${RESERVED_ASSIGNMENT_PAYLOAD}"
pass "una maquinaria RESERVED no puede asignarse dos veces"

# 15. Asignar el equipo disponible al segundo request.
CANCEL_ASSIGNMENT_PAYLOAD="$(jq -n \
  --arg equipment_id "${FAR_EQUIPMENT_ID}" \
  '{
    equipmentId: $equipment_id,
    reason: "Asignación que será cancelada durante la prueba"
  }')"

call_api logistic POST \
  "/requests/${SECOND_REQUEST_ID}/assignment" \
  "201" \
  "${CANCEL_ASSIGNMENT_PAYLOAD}"

CANCEL_ASSIGNMENT_ID="$(extract_id)"
assert_valid_id "${CANCEL_ASSIGNMENT_ID}" "La asignación cancelable"
assert_json '.data.status == "ACTIVE"' \
  "la segunda asignación inicia en ACTIVE"

call_api fleet GET "/equipments/${FAR_EQUIPMENT_ID}" "200"
assert_json '(.data.status // .status) == "RESERVED"' \
  "la segunda asignación reserva la maquinaria distante"

# 16. Rechazar un estado desconocido para Assignment.
call_api logistic PATCH \
  "/assignments/${CANCEL_ASSIGNMENT_ID}/status" \
  "400" \
  '{
    "status": "UNKNOWN",
    "reason": "Estado inválido de prueba"
  }'

# 17. Cancelar la segunda asignación mediante MCP.
MCP_CANCEL_WITHOUT_CONFIRMATION="$(jq -cn \
  --arg assignment_id "${CANCEL_ASSIGNMENT_ID}" \
  '{
    assignmentId: $assignment_id,
    reason: "Prueba de cancelación sin confirmación",
    confirmed: false
  }')"

call_mcp_tool \
  "cancel_assignment" \
  "${MCP_CANCEL_WITHOUT_CONFIRMATION}" \
  "mcp-cancel-unconfirmed-${RUN_ID}"
assert_mcp_tool_error \
  "MCP rechaza cancelar una asignación sin confirmed=true"

call_api logistic GET "/requests/${SECOND_REQUEST_ID}/assignment" "200"
assert_json '.data.status == "ACTIVE"' \
  "la cancelación MCP no confirmada no modifica la asignación"

MCP_CANCEL_CONFIRMED="$(jq -cn \
  --arg assignment_id "${CANCEL_ASSIGNMENT_ID}" \
  '{
    assignmentId: $assignment_id,
    reason: "El cliente canceló el proyecto",
    confirmed: true
  }')"

call_mcp_tool \
  "cancel_assignment" \
  "${MCP_CANCEL_CONFIRMED}" \
  "mcp-cancel-confirmed-${RUN_ID}"
assert_mcp_success "MCP cancela la asignación confirmada"
assert_mcp_contains \
  "CANCELLED" \
  "la respuesta MCP contiene el estado CANCELLED"

call_api logistic GET "/requests/${SECOND_REQUEST_ID}" "200"
assert_json '(.data.status // .status) == "CANCELLED"' \
  "cancelar Assignment cambia el request a CANCELLED"

call_api fleet GET "/equipments/${FAR_EQUIPMENT_ID}" "200"
assert_json '(.data.status // .status) == "AVAILABLE"' \
  "cancelar Assignment libera la maquinaria"

call_api logistic PATCH \
  "/assignments/${CANCEL_ASSIGNMENT_ID}/status" \
  "422" \
  '{
    "status": "COMPLETED",
    "reason": "Intento desde un estado terminal"
  }'
pass "CANCELLED es un estado terminal"

# 18. Ejecutar el ciclo operacional del equipo de la asignación principal.
call_api fleet PATCH \
  "/equipments/${NEAR_EQUIPMENT_ID}/status" \
  "200" \
  '{
    "status": "IN_TRANSIT",
    "reason": "Traslado hacia el proyecto iniciado"
  }'

call_api fleet PATCH \
  "/equipments/${NEAR_EQUIPMENT_ID}/status" \
  "200" \
  '{
    "status": "WORKING",
    "reason": "Maquinaria recibida en el proyecto"
  }'

# 19. Completar Assignment mediante MCP debe completar el request y liberar el equipo.
MCP_COMPLETE_WITHOUT_CONFIRMATION="$(jq -cn \
  --arg assignment_id "${ASSIGNMENT_ID}" \
  '{
    assignmentId: $assignment_id,
    reason: "Prueba de finalización sin confirmación",
    confirmed: false
  }')"

call_mcp_tool \
  "complete_assignment" \
  "${MCP_COMPLETE_WITHOUT_CONFIRMATION}" \
  "mcp-complete-unconfirmed-${RUN_ID}"
assert_mcp_tool_error \
  "MCP rechaza completar una asignación sin confirmed=true"

call_api logistic GET "/requests/${REQUEST_ID}/assignment" "200"
assert_json '.data.status == "ACTIVE"' \
  "la finalización MCP no confirmada no modifica la asignación"

MCP_COMPLETE_CONFIRMED="$(jq -cn \
  --arg assignment_id "${ASSIGNMENT_ID}" \
  '{
    assignmentId: $assignment_id,
    reason: "Operación logística completada",
    confirmed: true
  }')"

call_mcp_tool \
  "complete_assignment" \
  "${MCP_COMPLETE_CONFIRMED}" \
  "mcp-complete-confirmed-${RUN_ID}"
assert_mcp_success "MCP completa la asignación confirmada"
assert_mcp_contains \
  "COMPLETED" \
  "la respuesta MCP contiene el estado COMPLETED"

# 20. Verificar el estado final de las tres entidades.
call_api logistic GET "/requests/${REQUEST_ID}" "200"
assert_json '(.data.status // .status) == "COMPLETED"' \
  "completar Assignment cambia el request a COMPLETED"

call_api fleet GET "/equipments/${NEAR_EQUIPMENT_ID}" "200"
assert_json '(.data.status // .status) == "AVAILABLE"' \
  "completar Assignment devuelve la maquinaria a AVAILABLE"

call_api logistic GET "/requests/${REQUEST_ID}/assignment" "200"
assert_json '.data.status == "COMPLETED"' \
  "consultar por request devuelve Assignment COMPLETED"

call_api logistic GET "/assignments?status=COMPLETED&page=1&pageSize=100" "200"
assert_json \
  ".data | any(.id == \"${ASSIGNMENT_ID}\" and .status == \"COMPLETED\")" \
  "el listado filtrado contiene el Assignment COMPLETED"

# 21. Verificar los historiales de Request y Equipment.
call_api logistic GET "/requests/${REQUEST_ID}/status-history" "200"
assert_json \
  '[.. | objects | select(.fromStatus? == "PENDING" and .toStatus? == "ASSIGNED")] | length > 0' \
  "historial de solicitud contiene PENDING -> ASSIGNED"
assert_json \
  '[.. | objects | select(.fromStatus? == "ASSIGNED" and .toStatus? == "COMPLETED")] | length > 0' \
  "historial de solicitud contiene ASSIGNED -> COMPLETED"

call_api fleet GET "/equipments/${NEAR_EQUIPMENT_ID}/status-history" "200"
assert_json \
  '[.. | objects | select(.fromStatus? == "AVAILABLE" and .toStatus? == "RESERVED")] | length > 0' \
  "historial de equipo contiene AVAILABLE -> RESERVED"
assert_json \
  '[.. | objects | select(.fromStatus? == "RESERVED" and .toStatus? == "IN_TRANSIT")] | length > 0' \
  "historial de equipo contiene RESERVED -> IN_TRANSIT"
assert_json \
  '[.. | objects | select(.fromStatus? == "IN_TRANSIT" and .toStatus? == "WORKING")] | length > 0' \
  "historial de equipo contiene IN_TRANSIT -> WORKING"
assert_json \
  '[.. | objects | select(.fromStatus? == "WORKING" and .toStatus? == "AVAILABLE")] | length > 0' \
  "historial de equipo contiene WORKING -> AVAILABLE"

# 22. Una asignación COMPLETED no puede modificarse otra vez.
call_api logistic PATCH \
  "/assignments/${ASSIGNMENT_ID}/status" \
  "422" \
  '{
    "status": "CANCELLED",
    "reason": "Intento desde estado terminal"
  }'
pass "COMPLETED es un estado terminal"

# 23. Un Assignment inexistente devuelve 404.
NOT_FOUND_ASSIGNMENT_ID="11111111-1111-4111-8111-111111111111"

call_api logistic PATCH \
  "/assignments/${NOT_FOUND_ASSIGNMENT_ID}/status" \
  "404" \
  '{
    "status": "CANCELLED",
    "reason": "Asignación inexistente"
  }'

# 24. Retirar los equipos de la flota al terminar.
call_api fleet DELETE \
  "/fleets/${FLEET_ID}/equipments/${NEAR_EQUIPMENT_ID}" \
  "204"

call_api fleet DELETE \
  "/fleets/${FLEET_ID}/equipments/${FAR_EQUIPMENT_ID}" \
  "204"

echo
echo "Todas las pruebas integradas finalizaron correctamente."
echo "FLEET_ID=${FLEET_ID}"
echo "NEAR_EQUIPMENT_ID=${NEAR_EQUIPMENT_ID}"
echo "FAR_EQUIPMENT_ID=${FAR_EQUIPMENT_ID}"
echo "REQUEST_ID=${REQUEST_ID}"
echo "SECOND_REQUEST_ID=${SECOND_REQUEST_ID}"
echo "ASSIGNMENT_ID=${ASSIGNMENT_ID}"
echo "CANCEL_ASSIGNMENT_ID=${CANCEL_ASSIGNMENT_ID}"