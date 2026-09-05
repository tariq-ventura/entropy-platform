#!/usr/bin/env bash
set -euo pipefail

# Prueba end-to-end de fleet-service + logistic-service.
#
# Requisitos:
#   - curl
#   - jq
#   - fleet-service ejecutándose
#   - logistic-service ejecutándose y configurado para consultar fleet-service
#
# Uso local:
#   chmod +x fleet-logistic-e2e-test.sh
#   ./fleet-logistic-e2e-test.sh
#
# URLs personalizadas:
#   FLEET_BASE_URL=http://localhost:3000/api/v1 \
#   LOGISTIC_BASE_URL=http://localhost:3001/api/v1 \
#   ./fleet-logistic-e2e-test.sh

FLEET_BASE_URL="${FLEET_BASE_URL:-http://localhost:3000/api/v1}"
LOGISTIC_BASE_URL="${LOGISTIC_BASE_URL:-http://localhost:3001/api/v1}"
RUN_ID="${RUN_ID:-$(date +%s)}"
BODY_FILE="$(mktemp)"

HTTP_STATUS=""
FLEET_ID=""
NEAR_EQUIPMENT_ID=""
FAR_EQUIPMENT_ID=""
REQUEST_ID=""

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
      --output "${BODY_FILE}" \
      --write-out '%{http_code}' \
      --request "${method}" \
      --header 'Content-Type: application/json' \
      --data "${payload}" \
      "${base_url}${path}")"
  else
    HTTP_STATUS="$(curl --silent --show-error \
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
echo "RUN_ID:       ${RUN_ID}"

# 1. Comprobar que ambos servicios responden.
call_api fleet GET "/equipments?page=1&pageSize=1" "200"
pass "fleet-service está disponible"

call_api logistic GET "/requests?page=1&pageSize=1" "200"
pass "logistic-service está disponible"

# 2. Crear una flota.
FLEET_PAYLOAD="$(jq -n \
  --arg code "FLEET-E2E-${RUN_ID}" \
  --arg name "Flota E2E ${RUN_ID}" \
  '{code: $code, name: $name}')"

call_api fleet POST "/fleets" "201" "${FLEET_PAYLOAD}"
FLEET_ID="$(extract_id)"
assert_valid_id "${FLEET_ID}" "La flota"
pass "flota creada: ${FLEET_ID}"

# 3. Crear una excavadora cercana, con buen margen de mantenimiento.
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

# 4. Crear otra excavadora más distante y con menor margen.
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

# 5. Agregar ambas maquinarias a la flota.
call_api fleet PUT "/fleets/${FLEET_ID}/equipments/${NEAR_EQUIPMENT_ID}" "200"
call_api fleet PUT "/fleets/${FLEET_ID}/equipments/${FAR_EQUIPMENT_ID}" "200"

call_api fleet GET "/fleets/${FLEET_ID}/equipments" "200"
assert_json \
  "[.. | objects | .id? | select(. == \"${NEAR_EQUIPMENT_ID}\")] | length > 0" \
  "la flota contiene la maquinaria cercana"
assert_json \
  "[.. | objects | .id? | select(. == \"${FAR_EQUIPMENT_ID}\")] | length > 0" \
  "la flota contiene la maquinaria distante"

# 6. Crear una solicitud logística PENDING en San Miguel.
REQUEST_PAYLOAD="$(jq -n \
  --arg project_name "Proyecto integrado ${RUN_ID}" \
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

call_api logistic POST "/requests" "201" "${REQUEST_PAYLOAD}"
REQUEST_ID="$(extract_id)"
assert_valid_id "${REQUEST_ID}" "La solicitud logística"
assert_json '(.data.status // .status) == "PENDING"' \
  "la solicitud inicia en PENDING"
pass "solicitud creada: ${REQUEST_ID}"

# 7. Logistics consulta Fleet y genera las recomendaciones.
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

# 8. Reservar el equipo mejor recomendado desde Fleet.
RESERVE_PAYLOAD='{
  "status": "RESERVED",
  "reason": "Reservada por prueba integrada de recomendaciones"
}'

call_api fleet PATCH \
  "/equipments/${NEAR_EQUIPMENT_ID}/status" \
  "200" \
  "${RESERVE_PAYLOAD}"

# 9. La siguiente recomendación ya no debe incluir el equipo reservado.
call_api logistic GET "/requests/${REQUEST_ID}/recommendations" "200"

assert_json \
  ".data.recommendations | all(.equipmentId != \"${NEAR_EQUIPMENT_ID}\")" \
  "la maquinaria RESERVED queda fuera de las recomendaciones"
assert_json \
  ".data.recommendations | any(.equipmentId == \"${FAR_EQUIPMENT_ID}\")" \
  "la maquinaria AVAILABLE continúa disponible"

# 10. Confirmar la solicitud logística.
ASSIGN_REQUEST_PAYLOAD='{
  "status": "ASSIGNED",
  "reason": "Se confirmó la maquinaria recomendada"
}'

call_api logistic PATCH \
  "/requests/${REQUEST_ID}/status" \
  "200" \
  "${ASSIGN_REQUEST_PAYLOAD}"

# Una solicitud ASSIGNED ya no acepta nuevas recomendaciones.
call_api logistic GET "/requests/${REQUEST_ID}/recommendations" "409"
pass "una solicitud ASSIGNED no genera nuevas recomendaciones"

# 11. Ejecutar el ciclo operacional del equipo.
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

# 12. Completar la solicitud y liberar la maquinaria.
call_api logistic PATCH \
  "/requests/${REQUEST_ID}/status" \
  "200" \
  '{
    "status": "COMPLETED",
    "reason": "Operación logística completada"
  }'

call_api fleet PATCH \
  "/equipments/${NEAR_EQUIPMENT_ID}/status" \
  "200" \
  '{
    "status": "AVAILABLE",
    "reason": "Trabajo terminado y maquinaria liberada"
  }'

# 13. Verificar el estado final de ambas entidades.
call_api logistic GET "/requests/${REQUEST_ID}" "200"
assert_json '(.data.status // .status) == "COMPLETED"' \
  "la solicitud finaliza en COMPLETED"

call_api fleet GET "/equipments/${NEAR_EQUIPMENT_ID}" "200"
assert_json '(.data.status // .status) == "AVAILABLE"' \
  "la maquinaria vuelve a AVAILABLE"

# 14. Verificar los historiales de los dos microservicios.
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

# 15. Retirar los equipos de la flota al terminar.
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
