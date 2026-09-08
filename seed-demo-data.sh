#!/usr/bin/env bash

set -Eeuo pipefail

FLEET_BASE_URL="${FLEET_BASE_URL:-http://localhost:3000/api/v1}"
LOGISTIC_BASE_URL="${LOGISTIC_BASE_URL:-http://localhost:3001/api/v1}"
FLEET_TOKEN="${FLEET_TOKEN:-}"
LOGISTIC_TOKEN="${LOGISTIC_TOKEN:-}"
DEMO_RUN="${DEMO_RUN:-$(date -u +%Y%m%d%H%M%S)}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-5}"
CURL_MAX_TIME="${CURL_MAX_TIME:-30}"

BODY_FILE="$(mktemp)"
trap 'rm -f "${BODY_FILE}"' EXIT

log() {
  printf '\n[%s] %s\n' "$1" "$2"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  if [[ -s "${BODY_FILE}" ]]; then
    jq . "${BODY_FILE}" 2>/dev/null || sed -n '1,120p' "${BODY_FILE}"
  fi
  exit 1
}

api() {
  local service="$1"
  local method="$2"
  local path="$3"
  local payload="${4:-}"
  local base_url token status
  local -a args

  case "${service}" in
    fleet)
      base_url="${FLEET_BASE_URL%/}"
      token="${FLEET_TOKEN}"
      ;;
    logistic)
      base_url="${LOGISTIC_BASE_URL%/}"
      token="${LOGISTIC_TOKEN}"
      ;;
    *)
      fail "Servicio desconocido: ${service}"
      ;;
  esac

  args=(
    --silent
    --show-error
    --connect-timeout "${CURL_CONNECT_TIMEOUT}"
    --max-time "${CURL_MAX_TIME}"
    --output "${BODY_FILE}"
    --write-out '%{http_code}'
    --request "${method}"
    --header 'Accept: application/json'
  )

  if [[ -n "${token}" ]]; then
    args+=(--header "Authorization: Bearer ${token}")
  fi

  if [[ -n "${payload}" ]]; then
    args+=(
      --header 'Content-Type: application/json'
      --data "${payload}"
    )
  fi

  status="$(curl "${args[@]}" "${base_url}${path}")"

  if [[ ! "${status}" =~ ^2[0-9][0-9]$ ]]; then
    fail "${service} ${method} ${path} respondió HTTP ${status}"
  fi
}

extract_id() {
  jq -er '.data.id // .id' "${BODY_FILE}"
}

create_fleet() {
  local code="$1"
  local name="$2"
  local payload

  payload="$(jq -n \
    --arg code "${code}" \
    --arg name "${name}" \
    '{code: $code, name: $name}')"

  api fleet POST '/fleets' "${payload}"
  extract_id
}

create_equipment() {
  local code="$1"
  local brand="$2"
  local model="$3"
  local serial="$4"
  local year="$5"
  local capacity="$6"
  local location_name="$7"
  local latitude="$8"
  local longitude="$9"
  local engine_hours="${10}"
  local maintenance_interval="${11}"
  local fuel_percent="${12}"
  local payload

  payload="$(jq -n \
    --arg code "${code}" \
    --arg brand "${brand}" \
    --arg model "${model}" \
    --arg serial "${serial}" \
    --arg location_name "${location_name}" \
    --argjson year "${year}" \
    --argjson capacity "${capacity}" \
    --argjson latitude "${latitude}" \
    --argjson longitude "${longitude}" \
    --argjson engine_hours "${engine_hours}" \
    --argjson maintenance_interval "${maintenance_interval}" \
    --argjson fuel_percent "${fuel_percent}" \
    '{
      code: $code,
      type: "EXCAVATOR",
      brand: $brand,
      model: $model,
      serialNumber: $serial,
      year: $year,
      capacityTons: $capacity,
      location: {
        name: $location_name,
        latitude: $latitude,
        longitude: $longitude
      },
      engineHours: $engine_hours,
      maintenanceIntervalHours: $maintenance_interval,
      fuelPercent: $fuel_percent
    }')"

  api fleet POST '/equipments' "${payload}"
  extract_id
}

attach_equipment() {
  local fleet_id="$1"
  local equipment_id="$2"

  api fleet PUT "/fleets/${fleet_id}/equipments/${equipment_id}"
}

update_equipment_status() {
  local equipment_id="$1"
  local status="$2"
  local reason="$3"
  local payload

  payload="$(jq -n \
    --arg status "${status}" \
    --arg reason "${reason}" \
    '{status: $status, reason: $reason}')"

  api fleet PATCH "/equipments/${equipment_id}/status" "${payload}"
}

create_request() {
  local equipment_type="$1"
  local project_name="$2"
  local location_name="$3"
  local latitude="$4"
  local longitude="$5"
  local start_date="$6"
  local end_date="$7"
  local payload

  payload="$(jq -n \
    --arg equipment_type "${equipment_type}" \
    --arg project_name "${project_name}" \
    --arg location_name "${location_name}" \
    --arg start_date "${start_date}" \
    --arg end_date "${end_date}" \
    --argjson latitude "${latitude}" \
    --argjson longitude "${longitude}" \
    '{
      equipmentType: $equipment_type,
      projectName: $project_name,
      location: {
        name: $location_name,
        latitude: $latitude,
        longitude: $longitude
      },
      startDate: $start_date,
      endDate: $end_date
    }')"

  api logistic POST '/requests' "${payload}"
  extract_id
}

create_assignment() {
  local request_id="$1"
  local equipment_id="$2"
  local reason="$3"
  local payload

  payload="$(jq -n \
    --arg equipment_id "${equipment_id}" \
    --arg reason "${reason}" \
    '{equipmentId: $equipment_id, reason: $reason}')"

  api logistic POST "/requests/${request_id}/assignment" "${payload}"
  extract_id
}

update_assignment_status() {
  local assignment_id="$1"
  local status="$2"
  local reason="$3"
  local payload

  payload="$(jq -n \
    --arg status "${status}" \
    --arg reason "${reason}" \
    '{status: $status, reason: $reason}')"

  api logistic PATCH "/assignments/${assignment_id}/status" "${payload}"
}

log setup "Validando servicios"
api fleet GET '/equipments?page=1&pageSize=1'
api logistic GET '/requests?page=1&pageSize=1'

log fleet "Creando flotas de demostración"
CENTRAL_FLEET_ID="$(create_fleet \
  "DEMO-CENTRAL-${DEMO_RUN}" \
  'Flota Central')"

EAST_FLEET_ID="$(create_fleet \
  "DEMO-ORIENTE-${DEMO_RUN}" \
  'Flota Oriente')"

log fleet "Creando inventario de maquinaria"
SS_EQUIPMENT_ID="$(create_equipment \
  "DEMO-SS-${DEMO_RUN}" 'Caterpillar' '320' \
  "DEMO-SS-SERIAL-${DEMO_RUN}" 2026 23 \
  'San Salvador - Escalón' 13.7022 -89.2299 \
  120 500 95)"

SANTA_TECLA_EQUIPMENT_ID="$(create_equipment \
  "DEMO-ST-${DEMO_RUN}" 'Caterpillar' '323' \
  "DEMO-ST-SERIAL-${DEMO_RUN}" 2025 25 \
  'Santa Tecla' 13.6769 -89.2797 \
  310 450 82)"

SANTA_ANA_EQUIPMENT_ID="$(create_equipment \
  "DEMO-SA-${DEMO_RUN}" 'John Deere' '210G' \
  "DEMO-SA-SERIAL-${DEMO_RUN}" 2024 22 \
  'Santa Ana' 13.9942 -89.5597 \
  650 300 68)"

SOYAPANGO_EQUIPMENT_ID="$(create_equipment \
  "DEMO-SOY-${DEMO_RUN}" 'Volvo' 'EC220E' \
  "DEMO-SOY-SERIAL-${DEMO_RUN}" 2025 22 \
  'Soyapango' 13.7100 -89.1400 \
  260 400 76)"

SAN_MIGUEL_EQUIPMENT_ID="$(create_equipment \
  "DEMO-SM-${DEMO_RUN}" 'Komatsu' 'PC210LC' \
  "DEMO-SM-SERIAL-${DEMO_RUN}" 2026 23 \
  'San Miguel' 13.4833 -88.1833 \
  180 500 91)"

RESERVED_EQUIPMENT_ID="$(create_equipment \
  "DEMO-SM-R-${DEMO_RUN}" 'Caterpillar' '330' \
  "DEMO-SM-R-SERIAL-${DEMO_RUN}" 2025 30 \
  'San Miguel' 13.4825 -88.1815 \
  410 350 72)"

USULUTAN_EQUIPMENT_ID="$(create_equipment \
  "DEMO-USU-${DEMO_RUN}" 'Hyundai' 'HX220L' \
  "DEMO-USU-SERIAL-${DEMO_RUN}" 2024 22 \
  'Usulután' 13.3458 -88.4375 \
  540 300 64)"

MAINTENANCE_EQUIPMENT_ID="$(create_equipment \
  "DEMO-LU-M-${DEMO_RUN}" 'CASE' 'CX220C' \
  "DEMO-LU-M-SERIAL-${DEMO_RUN}" 2023 22 \
  'La Unión' 13.3369 -87.8439 \
  890 50 38)"

log fleet "Asignando maquinaria a sus flotas"
for equipment_id in \
  "${SS_EQUIPMENT_ID}" \
  "${SANTA_TECLA_EQUIPMENT_ID}" \
  "${SANTA_ANA_EQUIPMENT_ID}" \
  "${SOYAPANGO_EQUIPMENT_ID}"; do
  attach_equipment "${CENTRAL_FLEET_ID}" "${equipment_id}"
done

for equipment_id in \
  "${SAN_MIGUEL_EQUIPMENT_ID}" \
  "${RESERVED_EQUIPMENT_ID}" \
  "${USULUTAN_EQUIPMENT_ID}" \
  "${MAINTENANCE_EQUIPMENT_ID}"; do
  attach_equipment "${EAST_FLEET_ID}" "${equipment_id}"
done

update_equipment_status \
  "${MAINTENANCE_EQUIPMENT_ID}" \
  'MAINTENANCE' \
  'Mantenimiento preventivo programado para la demostración'

log logistic "Creando solicitud pendiente con recomendaciones"
PENDING_REQUEST_ID="$(create_request \
  'EXCAVATOR' \
  "Proyecto Escalón Galerías ${DEMO_RUN}" \
  'P.º Gral. Escalón 3700, San Salvador, El Salvador' \
  13.7022056 -89.2299316 \
  '2030-09-10T08:00:00Z' \
  '2030-09-15T17:00:00Z')"

log logistic "Creando una asignación activa con equipo RESERVED"
RESERVED_REQUEST_ID="$(create_request \
  'EXCAVATOR' \
  "Proyecto Metrocentro San Miguel ${DEMO_RUN}" \
  'San Miguel, El Salvador' \
  13.4833 -88.1833 \
  '2030-10-01T08:00:00Z' \
  '2030-10-20T17:00:00Z')"

RESERVED_ASSIGNMENT_ID="$(create_assignment \
  "${RESERVED_REQUEST_ID}" \
  "${RESERVED_EQUIPMENT_ID}" \
  'Maquinaria reservada para entrega programada')"

log logistic "Creando una asignación activa con equipo WORKING"
WORKING_REQUEST_ID="$(create_request \
  'EXCAVATOR' \
  "Proyecto Industrial Soyapango ${DEMO_RUN}" \
  'Soyapango, San Salvador, El Salvador' \
  13.7100 -89.1400 \
  '2030-08-01T08:00:00Z' \
  '2030-11-30T17:00:00Z')"

WORKING_ASSIGNMENT_ID="$(create_assignment \
  "${WORKING_REQUEST_ID}" \
  "${SOYAPANGO_EQUIPMENT_ID}" \
  'Maquinaria asignada a operación industrial')"

update_equipment_status \
  "${SOYAPANGO_EQUIPMENT_ID}" \
  'IN_TRANSIT' \
  'Traslado hacia el proyecto'

update_equipment_status \
  "${SOYAPANGO_EQUIPMENT_ID}" \
  'WORKING' \
  'Maquinaria recibida y operando en el proyecto'

log logistic "Creando historial COMPLETED"
COMPLETED_REQUEST_ID="$(create_request \
  'EXCAVATOR' \
  "Proyecto finalizado Usulután ${DEMO_RUN}" \
  'Usulután, El Salvador' \
  13.3458 -88.4375 \
  '2030-05-01T08:00:00Z' \
  '2030-05-15T17:00:00Z')"

COMPLETED_ASSIGNMENT_ID="$(create_assignment \
  "${COMPLETED_REQUEST_ID}" \
  "${USULUTAN_EQUIPMENT_ID}" \
  'Asignación histórica para la demostración')"

update_equipment_status \
  "${USULUTAN_EQUIPMENT_ID}" \
  'IN_TRANSIT' \
  'Traslado histórico hacia el proyecto'

update_equipment_status \
  "${USULUTAN_EQUIPMENT_ID}" \
  'WORKING' \
  'Operación histórica iniciada'

update_assignment_status \
  "${COMPLETED_ASSIGNMENT_ID}" \
  'COMPLETED' \
  'Operación finalizada satisfactoriamente'

log logistic "Creando historial CANCELLED"
CANCELLED_REQUEST_ID="$(create_request \
  'EXCAVATOR' \
  "Proyecto cancelado Santa Ana ${DEMO_RUN}" \
  'Santa Ana, El Salvador' \
  13.9942 -89.5597 \
  '2030-06-01T08:00:00Z' \
  '2030-06-08T17:00:00Z')"

CANCELLED_ASSIGNMENT_ID="$(create_assignment \
  "${CANCELLED_REQUEST_ID}" \
  "${SANTA_ANA_EQUIPMENT_ID}" \
  'Asignación que será cancelada para mostrar el historial')"

update_assignment_status \
  "${CANCELLED_ASSIGNMENT_ID}" \
  'CANCELLED' \
  'Proyecto cancelado por el cliente'

log validation "Comprobando que la solicitud pendiente tenga recomendaciones"
api logistic GET "/requests/${PENDING_REQUEST_ID}/recommendations"
RECOMMENDATION_COUNT="$(jq -er '.data.count // .count' "${BODY_FILE}")"

if (( RECOMMENDATION_COUNT < 1 )); then
  fail 'La solicitud pendiente no produjo recomendaciones'
fi

log done "Datos de demostración creados correctamente"

jq -n \
  --arg demoRun "${DEMO_RUN}" \
  --arg centralFleetId "${CENTRAL_FLEET_ID}" \
  --arg eastFleetId "${EAST_FLEET_ID}" \
  --arg pendingRequestId "${PENDING_REQUEST_ID}" \
  --arg reservedRequestId "${RESERVED_REQUEST_ID}" \
  --arg reservedAssignmentId "${RESERVED_ASSIGNMENT_ID}" \
  --arg workingRequestId "${WORKING_REQUEST_ID}" \
  --arg workingAssignmentId "${WORKING_ASSIGNMENT_ID}" \
  --arg completedRequestId "${COMPLETED_REQUEST_ID}" \
  --arg completedAssignmentId "${COMPLETED_ASSIGNMENT_ID}" \
  --arg cancelledRequestId "${CANCELLED_REQUEST_ID}" \
  --arg cancelledAssignmentId "${CANCELLED_ASSIGNMENT_ID}" \
  --argjson recommendations "${RECOMMENDATION_COUNT}" \
  '{
    demoRun: $demoRun,
    fleets: {
      central: $centralFleetId,
      east: $eastFleetId
    },
    requests: {
      pending: $pendingRequestId,
      reserved: $reservedRequestId,
      working: $workingRequestId,
      completed: $completedRequestId,
      cancelled: $cancelledRequestId
    },
    assignments: {
      reserved: $reservedAssignmentId,
      working: $workingAssignmentId,
      completed: $completedAssignmentId,
      cancelled: $cancelledAssignmentId
    },
    recommendationCount: $recommendations
  }'
