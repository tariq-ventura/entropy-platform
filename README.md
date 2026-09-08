# Entropy Platform

Plataforma inteligente para administrar flotas de maquinaria pesada, registrar solicitudes logísticas, recomendar el equipo más conveniente y controlar su asignación durante todo el ciclo operativo.

El MVP integra:

- `fleet-service`: flotas, maquinaria, ubicación y estados operativos;
- `logistic-service`: solicitudes, búsqueda híbrida, recomendaciones y asignaciones;
- `entropy-mcp-server`: herramientas seguras para asistentes y automatizaciones;
- `n8n`: conversación, geocodificación y orquestación del asistente;
- PostgreSQL con `pgvector`: datos operativos y búsqueda semántica;
- Ollama en local y Vertex AI en Google Cloud para generar embeddings.

> Estado actual: el backend funcional y su flujo integrado están implementados y cubiertos por pruebas E2E. El frontend Next.js y el despliegue productivo en GCP forman parte de la siguiente etapa.

## Contenido

- [Qué puede hacer el MVP](#qué-puede-hacer-el-mvp)
- [Arquitectura](#arquitectura)
- [Estructura de repositorios](#estructura-de-repositorios)
- [Tecnologías](#tecnologías)
- [Inicio rápido](#inicio-rápido)
- [Configuración](#configuración)
- [API de Fleet](#api-de-fleet)
- [API de Logistics](#api-de-logistics)
- [Búsqueda literal, geográfica y vectorial](#búsqueda-literal-geográfica-y-vectorial)
- [Algoritmo de recomendaciones](#algoritmo-de-recomendaciones)
- [Ciclo de asignaciones](#ciclo-de-asignaciones)
- [MCP Server](#mcp-server)
- [Flujo de n8n](#flujo-de-n8n)
- [Pruebas E2E](#pruebas-e2e)
- [Observabilidad](#observabilidad)
- [Arquitectura objetivo en GCP](#arquitectura-objetivo-en-gcp)
- [Desarrollo con submódulos](#desarrollo-con-submódulos)
- [Solución de problemas](#solución-de-problemas)
- [Limitaciones del MVP](#limitaciones-del-mvp)

## Qué puede hacer el MVP

### Gestión de flota

- Crear, consultar, actualizar y eliminar flotas.
- Crear, consultar, filtrar, actualizar y eliminar maquinaria.
- Agregar o retirar maquinaria de una flota mediante `Equipment.FleetID`.
- Buscar equipos por texto y filtrar por estado.
- Cambiar el estado operativo de una máquina y conservar su historial.
- Evitar códigos y números de serie duplicados con respuestas HTTP correctas, por ejemplo `409 Conflict`.
- Generar UUID aleatorios para las entidades, en lugar de identificadores incrementales o UUID cero.

### Operación logística

- Crear y mantener solicitudes de maquinaria.
- Controlar el ciclo de estados de cada solicitud.
- Buscar solicitudes por texto literal, significado y proximidad geográfica.
- Recomendar solamente maquinaria compatible y disponible.
- Ordenar las recomendaciones con un algoritmo determinista y explicable.
- Crear una asignación a partir de una recomendación.
- Reservar la maquinaria en Fleet al asignarla.
- Completar o cancelar una asignación y liberar la maquinaria.
- Impedir asignaciones duplicadas y operaciones incompatibles con el estado actual.

### Asistente y automatización

- Exponer las operaciones logísticas como herramientas MCP.
- Consultar solicitudes con lenguaje natural sin pedir UUID constantemente.
- Convertir una dirección escrita por el usuario en coordenadas mediante Google Maps en n8n.
- Exigir confirmación antes de ejecutar acciones operativas sensibles.
- Mantener al LLM fuera de la base de datos: el asistente solo puede actuar mediante APIs y herramientas autorizadas.

## Arquitectura

```mermaid
flowchart TD
    U["Usuario"] --> N["n8n · chat y agente"]
    N --> M["Entropy MCP Server"]
    N --> G["Google Maps · geocoding"]
    M --> L["Logistic Service"]
    L --> F["Fleet Service"]
    F --> PF[("fleet_db")]
    L --> PL[("logistics_db + pgvector")]
    L --> E["Ollama local / Vertex AI cloud"]
```

El flujo HTTP normal sigue disponible para el frontend y para integraciones directas. MCP no sustituye las APIs; ofrece una capa de herramientas controladas para agentes de IA.

### Responsabilidades

| Componente | Responsabilidad |
| --- | --- |
| `fleet-service` | Fuente de verdad de flotas, equipos, ubicación, telemetría básica y estado operativo. |
| `logistic-service` | Solicitudes, búsqueda, recomendaciones, asignaciones y reglas de negocio logísticas. |
| `entropy-mcp-server` | Traduce llamadas MCP en operaciones de Logistics sin exponer la base de datos. |
| `n8n` | Recibe mensajes, coordina el modelo, geocodifica ubicaciones y presenta confirmaciones. |
| PostgreSQL | Mantiene datos relacionales en dos bases independientes. |
| `pgvector` | Almacena embeddings y calcula similitud semántica. |
| Ollama / Vertex AI | Genera embeddings; no decide qué maquinaria debe asignarse. |

## Estructura de repositorios

El repositorio padre integra tres submódulos:

```text
entropy-platform/
├── entropy-mcp-server/        # Servidor MCP en Go
├── fleet-service/             # Dominio de flotas y maquinaria
├── logistic-service/          # Dominio de solicitudes y asignaciones
├── postgres/
│   └── init.sql               # Crea fleet_db y logistics_db
├── compose.yaml               # Entorno integrado local
├── fleet-logistic-e2e-test.sh # Suite de integración completa
├── seed-demo-data.sh          # Datos consistentes para la demo
└── README.md
```

Cada microservicio conserva su propio código, migraciones, `go.mod`, `Dockerfile` y pruebas unitarias. El repositorio padre fija versiones compatibles y contiene los elementos de integración.

## Tecnologías

| Área | Tecnología |
| --- | --- |
| Backend | Go, Gin y GORM |
| Base de datos | PostgreSQL 17 y `pgvector` |
| Identificadores | UUID v4 |
| Contrato de IA | Model Context Protocol (MCP) |
| Automatización | n8n |
| Embeddings locales | Ollama + `nomic-embed-text-v2-moe` |
| Embeddings cloud | Vertex AI + `text-multilingual-embedding-002` |
| Geocodificación | Google Maps Geocoding API |
| Observabilidad | OpenTelemetry y logging estructurado |
| Contenedores | Docker y Docker Compose |
| Frontend planificado | Next.js en Cloud Run |
| Backend cloud planificado | GKE Autopilot |
| CI/CD planificado | GitHub, Cloud Build, Artifact Registry y Cloud Deploy |

## Inicio rápido

### Requisitos

- Git con soporte para submódulos;
- Docker Engine y Docker Compose;
- `curl` y `jq` para ejecutar la suite E2E;
- puertos `3000`, `3001`, `3002`, `5432`, `5678` y `11434` disponibles.

### 1. Clonar los submódulos

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

### 2. Levantar la plataforma

```bash
docker compose up -d --build
```

### 3. Descargar el modelo local de embeddings

La primera ejecución requiere descargar el modelo en el volumen de Ollama:

```bash
docker exec entropy-ollama ollama pull nomic-embed-text-v2-moe
```

### 4. Verificar los servicios

```bash
curl http://localhost:3000/health
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:5678/healthz
```

### Puertos locales

| Servicio | URL |
| --- | --- |
| Fleet API | `http://localhost:3000` |
| Logistics API | `http://localhost:3001` |
| MCP | `http://localhost:3002/mcp` |
| n8n | `http://localhost:5678` |
| Ollama | `http://localhost:11434` |
| PostgreSQL | `localhost:5432` |

## Configuración

Los nombres exactos pueden variar ligeramente entre submódulos. Estas son las variables relevantes de la integración.

### Fleet Service

```env
PORT=:3000
DB_CONTEXT=postgresql
DB_STRING=host=postgres user=app password=app_local_password dbname=fleet_db port=5432 sslmode=disable
```

### Logistic Service con Ollama

```env
PORT=:3001
DB_CONTEXT=postgresql
DB_STRING=host=postgres user=app password=app_local_password dbname=logistics_db port=5432 sslmode=disable
FLEET_SERVICE_URL=http://fleet-service:3000

EMBEDDING_PROVIDER=ollama
OLLAMA_URL=http://ollama:11434
OLLAMA_EMBEDDING_MODEL=nomic-embed-text-v2-moe
EMBEDDING_DIMENSIONS=768
```

### Logistic Service con Vertex AI

```env
EMBEDDING_PROVIDER=vertex
GCP_PROJECT_ID=my-gcp-project
VERTEX_LOCATION=us-central1
VERTEX_EMBEDDING_MODEL=text-multilingual-embedding-002
EMBEDDING_DIMENSIONS=768
```

La aplicación selecciona la implementación de embeddings mediante `EMBEDDING_PROVIDER`; los handlers y DTOs no dependen del proveedor.

### MCP Server

```env
PORT=:3002
LOGISTIC_SERVICE_URL=http://logistic-service:3001
MCP_API_KEY=entropy-local-secret
```

### n8n

```env
GENERIC_TIMEZONE=America/El_Salvador
TZ=America/El_Salvador
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_RUNNERS_ENABLED=true
```

La información de n8n se conserva en el volumen `n8n_data`.

Configuración equivalente en Compose:

```yaml
services:
  n8n:
    image: n8nio/n8n
    container_name: n8n
    ports:
      - "5678:5678"
    environment:
      GENERIC_TIMEZONE: America/El_Salvador
      TZ: America/El_Salvador
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: "true"
      N8N_RUNNERS_ENABLED: "true"
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
```

## Modelo principal de Equipment

```go
type Equipment struct {
    ID       uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
    Code     string     `json:"code" gorm:"size:50;not null;uniqueIndex"`
    FleetID  *uuid.UUID `json:"fleetId,omitempty" gorm:"type:uuid;index"`

    Type         EquipmentType `json:"type" gorm:"size:30;not null;index"`
    Brand        string        `json:"brand" gorm:"size:100;not null"`
    Model        string        `json:"model" gorm:"size:100;not null"`
    SerialNumber string        `json:"serialNumber" gorm:"size:100;not null;uniqueIndex"`
    Year         int           `json:"year" gorm:"not null"`

    CapacityTons float64         `json:"capacityTons" gorm:"type:numeric(8,2);not null"`
    Status       EquipmentStatus `json:"status" gorm:"size:30;not null;default:AVAILABLE;index"`
    Location     Location        `json:"location" gorm:"embedded"`

    EngineHours          float64 `json:"engineHours" gorm:"type:numeric(12,2);not null;default:0"`
    NextMaintenanceHours float64 `json:"nextMaintenanceHours" gorm:"type:numeric(12,2);not null"`
    FuelPercent          float64 `json:"fuelPercent" gorm:"type:numeric(5,2);not null"`

    CreatedAt time.Time `json:"createdAt"`
    UpdatedAt time.Time `json:"updatedAt"`
}

type Location struct {
    Name      string  `json:"name" gorm:"column:location_name;size:150;not null"`
    Latitude  float64 `json:"latitude" gorm:"column:latitude;not null"`
    Longitude float64 `json:"longitude" gorm:"column:longitude;not null"`
}
```

La relación se modela únicamente desde `Equipment.FleetID`. `Fleet` no necesita guardar un arreglo persistente de equipos; cuando se requiere, se consulta por la clave foránea.

## API de Fleet

Base URL local:

```text
http://localhost:3000/api/v1
```

### Flotas

| Método | Ruta | Función |
| --- | --- | --- |
| `POST` | `/fleets` | Crear flota. |
| `GET` | `/fleets` | Listar flotas con paginación. |
| `GET` | `/fleets/:fleetID` | Consultar una flota. |
| `PATCH` | `/fleets/:fleetID` | Actualizar campos editables. |
| `DELETE` | `/fleets/:fleetID` | Eliminar flota; responde `204`. |
| `GET` | `/fleets/:fleetID/equipments` | Listar equipos de la flota. |
| `PUT` | `/fleets/:fleetID/equipments/:equipmentID` | Agregar equipo a la flota. |
| `DELETE` | `/fleets/:fleetID/equipments/:equipmentID` | Retirar equipo de la flota. |

### Maquinaria

| Método | Ruta | Función |
| --- | --- | --- |
| `POST` | `/equipments` | Crear maquinaria. |
| `GET` | `/equipments` | Listar y filtrar maquinaria. |
| `GET` | `/equipments/:equipmentID` | Consultar maquinaria. |
| `PATCH` | `/equipments/:equipmentID` | Actualizar datos editables. |
| `DELETE` | `/equipments/:equipmentID` | Eliminar maquinaria; responde `204`. |
| `PATCH` | `/equipments/:equipmentID/status` | Cambiar estado con una razón. |
| `GET` | `/equipments/:equipmentID/status-history` | Consultar historial de estados. |

El listado general soporta filtros, por lo que no se requiere un endpoint duplicado para equipos disponibles:

```bash
curl 'http://localhost:3000/api/v1/equipments?page=1&pageSize=100&status=AVAILABLE&search=CAT'
```

### Estados de Equipment

```text
AVAILABLE · RESERVED · IN_TRANSIT · WORKING · MAINTENANCE · INACTIVE · RETIRED
```

Ejemplo de cambio de estado:

```bash
curl -X PATCH 'http://localhost:3000/api/v1/equipments/EQUIPMENT_ID/status' \
  -H 'Content-Type: application/json' \
  -d '{"status":"MAINTENANCE","reason":"Mantenimiento preventivo"}'
```

## API de Logistics

Base URL local:

```text
http://localhost:3001/api/v1
```

### Solicitudes

| Método | Ruta | Función |
| --- | --- | --- |
| `POST` | `/requests` | Crear una solicitud. |
| `GET` | `/requests` | Listar solicitudes. |
| `QUERY` | `/requests` | Ejecutar búsqueda literal, geográfica, semántica o híbrida. |
| `GET` | `/requests/:requestID` | Consultar una solicitud. |
| `PATCH` | `/requests/:requestID` | Actualizar una solicitud editable. |
| `PATCH` | `/requests/:requestID/status` | Cambiar su estado. |
| `GET` | `/requests/:requestID/status-history` | Consultar historial. |
| `GET` | `/requests/:requestID/recommendations` | Calcular recomendaciones. |

Ejemplo de creación:

```bash
curl -X POST 'http://localhost:3001/api/v1/requests' \
  -H 'Content-Type: application/json' \
  -d '{
    "equipmentType": "EXCAVATOR",
    "projectName": "Proyecto Escalón Galerías",
    "location": {
      "name": "P.º Gral. Escalón 3700, San Salvador, El Salvador",
      "latitude": 13.7022056,
      "longitude": -89.2299316
    },
    "description": "Excavación y preparación de terreno comercial",
    "requirements": "Capacidad mínima de veinte toneladas",
    "startDate": "2030-09-10T08:00:00Z",
    "endDate": "2030-09-15T17:00:00Z"
  }'
```

`location.name` es obligatorio. Las coordenadas pueden provenir del frontend o de la herramienta de Google Maps configurada en n8n.

### Estados de Request

```text
PENDING · ASSIGNED · COMPLETED · CANCELLED
```

Una solicitud `ASSIGNED`, `COMPLETED` o `CANCELLED` no puede editarse como si continuara pendiente. Las operaciones inválidas se rechazan con `409 Conflict` o `422 Unprocessable Entity`, según el tipo de conflicto.

### Asignaciones

| Método | Ruta | Función |
| --- | --- | --- |
| `POST` | `/requests/:requestID/assignment` | Crear una asignación. |
| `GET` | `/requests/:requestID/assignment` | Consultar la asignación de una solicitud. |
| `GET` | `/assignments` | Listar asignaciones; admite `status`, `page` y `pageSize`. |
| `GET` | `/assignments/:assignmentID` | Consultar una asignación. |
| `PATCH` | `/assignments/:assignmentID/status` | Completar o cancelar. |

Estados de Assignment:

```text
ACTIVE · COMPLETED · CANCELLED
```

## Búsqueda literal, geográfica y vectorial

La búsqueda se expone con el método `QUERY` para aceptar un cuerpo JSON sin confundirla con la creación de recursos.

> Nota de compatibilidad: `QUERY` no es tan universal como `GET` o `POST`. Antes de desplegar, se debe comprobar que el load balancer, WAF, cliente HTTP y gateway utilizados permitan este método.

### Campos admitidos

```json
{
  "query": "Galerías",
  "semanticQuery": "preparar terreno para construir una zona comercial",
  "statuses": ["PENDING"],
  "equipmentType": "EXCAVATOR",
  "near": {
    "latitude": 13.7022056,
    "longitude": -89.2299316,
    "radiusKm": 25
  },
  "minSemanticScore": 0.45,
  "page": 1,
  "pageSize": 20
}
```

| Campo | Comportamiento |
| --- | --- |
| `query` | Coincidencia literal con `ILIKE` sobre proyecto, ubicación y tipo. |
| `semanticQuery` | Similitud coseno entre embeddings. |
| `near` | Distancia Haversine y filtro opcional por radio. |
| `statuses` | Restringe los estados aceptados. |
| `equipmentType` | Restringe el tipo de maquinaria. |
| `minSemanticScore` | Umbral entre `0` y `1`; requiere `semanticQuery`. |
| `page`, `pageSize` | Paginación del resultado. |

Ejemplo:

```bash
curl -X QUERY 'http://localhost:3001/api/v1/requests' \
  -H 'Content-Type: application/json' \
  -d '{
    "semanticQuery": "equipo para levantar piezas metálicas pesadas",
    "statuses": ["PENDING"],
    "near": {"latitude": 13.7, "longitude": -89.22, "radiusKm": 50},
    "page": 1,
    "pageSize": 10
  }'
```

### Persistencia de embeddings

Los vectores viven en una tabla separada, por ejemplo `logistics_request_embeddings`, relacionada con la solicitud mediante `request_id`. El registro contiene:

- proveedor y modelo;
- texto normalizado utilizado para el embedding;
- vector de 768 dimensiones;
- fecha de actualización.

Se utiliza un índice HNSW con distancia coseno para evitar búsquedas secuenciales a medida que crece el volumen.

Los documentos y consultas usan el formato recomendado por el proveedor. Para Ollama se diferencian los prefijos de documento y consulta.

### Regla importante al cambiar de proveedor

No se deben comparar embeddings creados por modelos diferentes. Las consultas filtran `provider` y `model`; al cambiar Ollama por Vertex en una misma base se deben regenerar los embeddings existentes.

En la práctica se recomienda:

- desarrollo local: Ollama;
- DEV/PROD en GCP: Vertex AI;
- una base independiente por ambiente;
- un proceso explícito de reindexación si cambia el modelo.

## Algoritmo de recomendaciones

Las recomendaciones no las decide Gemini. `logistic-service` consulta Fleet y aplica reglas deterministas:

1. La solicitud debe estar en `PENDING`.
2. El equipo debe tener el mismo `equipmentType`.
3. El equipo debe estar `AVAILABLE`.
4. Debe tener margen positivo antes del siguiente mantenimiento.
5. Cada candidato recibe un score de `0` a `100`.
6. Los candidatos se ordenan de mayor a menor score.

Ponderación actual:

| Factor | Peso máximo | Objetivo |
| --- | ---: | --- |
| Cercanía | 60 puntos | Reducir tiempo y costo de traslado. |
| Mantenimiento | 25 puntos | Evitar asignar equipos próximos al servicio. |
| Combustible | 15 puntos | Favorecer equipos con mejor autonomía inicial. |

```mermaid
flowchart TD
    R["Request PENDING"] --> C["Equipos compatibles y AVAILABLE"]
    C --> S["Score: distancia + mantenimiento + combustible"]
    S --> O["Ranking descendente"]
    O --> A["Selección y Assignment"]
```

Una lista vacía no representa un fallo: indica que no existe maquinaria que cumpla todas las condiciones actuales.

## Ciclo de asignaciones

```mermaid
stateDiagram-v2
    [*] --> ACTIVE: crear assignment
    ACTIVE --> COMPLETED: trabajo finalizado
    ACTIVE --> CANCELLED: operación cancelada
    COMPLETED --> [*]
    CANCELLED --> [*]
```

### Creación

Al crear un Assignment:

- se valida que el request exista y esté `PENDING`;
- se valida que el equipo exista y esté `AVAILABLE`;
- se crea la asignación `ACTIVE`;
- el request cambia a `ASSIGNED`;
- Fleet cambia el equipo a `RESERVED`.

### Finalización

Al completar:

- Assignment cambia a `COMPLETED`;
- Request cambia a `COMPLETED`;
- Equipment vuelve a `AVAILABLE`.

### Cancelación

Al cancelar:

- Assignment cambia a `CANCELLED`;
- Request cambia a `CANCELLED`;
- Equipment vuelve a `AVAILABLE`.

Los estados terminales no pueden cambiar nuevamente. Para el MVP, Logistics coordina las llamadas HTTP a Fleet; la evolución a eventos con Pub/Sub se plantea cuando sea necesario desacoplar procesos asincrónicos y reconciliar fallos.

## MCP Server

Endpoint local:

```text
http://localhost:3002/mcp
```

La conexión utiliza transporte **Streamable HTTP** y autenticación Bearer:

```http
Authorization: Bearer entropy-local-secret
```

### Herramientas disponibles

| Tool | Función | Confirmación |
| --- | --- | --- |
| `create_logistics_request` | Crear una solicitud con ubicación, fechas, descripción y requisitos. | Conversacional en n8n. |
| `get_logistics_request` | Consultar una solicitud por ID. | No. |
| `search_logistics_requests` | Buscar por texto, semántica, estado, tipo y proximidad. | No. |
| `get_recommendations` | Obtener el ranking de maquinaria. | No. |
| `create_assignment` | Asignar un equipo a una solicitud. | `confirmed=true`. |
| `get_assignment` | Consultar la asignación asociada a una solicitud. | No. |
| `complete_assignment` | Completar y liberar el equipo. | `confirmed=true`. |
| `cancel_assignment` | Cancelar y liberar el equipo. | `confirmed=true`. |

### Compatibilidad del schema con Gemini

Los esquemas de entrada de las tools se declaran con un subconjunto simple de JSON Schema. Esto evita errores `400 Invalid JSON payload` del adaptador de Google Generative AI.

No se deben incluir en los parámetros publicados a Gemini construcciones como:

- tipos union generados como `type: ["null", "number"]`;
- `exclusiveMinimum`;
- restricciones avanzadas que el adaptador no reconozca.

Las validaciones estrictas siguen ejecutándose dentro de MCP y de `logistic-service`; simplificar el schema anunciado no elimina las reglas de negocio.

### Prueba manual de MCP

Inicializar una sesión y listar herramientas:

```bash
curl -X POST 'http://localhost:3002/mcp' \
  -H 'Authorization: Bearer entropy-local-secret' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{
    "jsonrpc":"2.0",
    "id":"init-1",
    "method":"initialize",
    "params":{
      "protocolVersion":"2026-07-28",
      "capabilities":{},
      "clientInfo":{"name":"manual-test","version":"1.0.0"}
    }
  }'
```

Para pruebas completas se recomienda la suite E2E, porque administra automáticamente el identificador de sesión y los headers del protocolo.

## Flujo de n8n

### Nodos recomendados

1. **Chat Trigger** recibe el mensaje.
2. **AI Agent** interpreta la intención y mantiene el contexto conversacional.
3. **Google Gemini Chat Model** genera la respuesta y decide qué tool solicitar.
4. **MCP Client Tool** expone las herramientas de Entropy al agente.
5. **Google Maps** geocodifica ubicaciones cuando el usuario no proporciona coordenadas.
6. **Chat Response** devuelve el resultado final.

### Configuración del MCP Client Tool

| Campo | Valor local |
| --- | --- |
| Endpoint | `http://entropy-mcp-server:3002/mcp` |
| Server Transport | `HTTP Streamable` |
| Authentication | Header/Bearer con `MCP_API_KEY` |
| Tools to Include | Todas durante la demo; limitar por rol en producción. |

El nombre `entropy-mcp-server` funciona entre contenedores de la misma red de Compose. Desde el host se utiliza `localhost:3002`.

### Chat Trigger

Cuando se utiliza un nodo explícito para responder, **Response Mode** debe configurarse como:

```text
Using Response Nodes
```

### Reglas del agente

- Solicitar los datos que falten antes de crear una petición.
- Usar Google Maps para resolver una ubicación; nunca inventar coordenadas.
- Usar `query` para coincidencias textuales y `semanticQuery` para conceptos.
- Usar `near` solamente con coordenadas verificadas.
- No enviar `minSemanticScore` en la primera búsqueda salvo que exista una razón concreta.
- Evitar combinar `query` y `semanticQuery` innecesariamente.
- Mostrar nombres y datos útiles al usuario; ocultar UUID salvo que sean necesarios.
- Pedir confirmación clara antes de asignar, completar o cancelar.
- No intentar consultar PostgreSQL directamente.

n8n no genera los embeddings: envía `semanticQuery` a MCP y `logistic-service` usa el proveedor configurado.

## Pruebas E2E

La suite integrada valida Fleet, Logistics, MCP, Ollama y las reglas entre servicios.

### Ejecutar

```bash
chmod +x fleet-logistic-e2e-test.sh

EMBEDDING_PROVIDER_EXPECTED=ollama \
OLLAMA_BASE_URL=http://localhost:11434 \
OLLAMA_EMBEDDING_MODEL=nomic-embed-text-v2-moe \
./fleet-logistic-e2e-test.sh
```

Variables opcionales:

```env
FLEET_BASE_URL=http://localhost:3000
LOGISTIC_BASE_URL=http://localhost:3001
MCP_BASE_URL=http://localhost:3002
MCP_API_KEY=entropy-local-secret
MCP_PROTOCOL_VERSION=2026-07-28
```

### Cobertura del flujo

La prueba:

1. comprueba la salud de los tres servicios;
2. valida autenticación, descubrimiento y catálogo MCP;
3. crea una flota y dos equipos con distancias diferentes;
4. incorpora ambos equipos a la flota;
5. crea solicitudes con descripción y requisitos;
6. valida búsquedas semánticas en escenarios de excavación y elevación;
7. valida filtros híbridos, distancia y ranking semántico relativo;
8. rechaza scores inválidos y búsquedas incompletas;
9. calcula recomendaciones y comprueba que el equipo cercano obtenga mayor score;
10. verifica que una mutación MCP sin confirmación no cambie datos;
11. crea una asignación confirmada;
12. comprueba `Request=ASSIGNED` y `Equipment=RESERVED`;
13. evita recomendaciones y asignaciones duplicadas;
14. cancela una asignación y libera el equipo;
15. completa otra asignación y libera el equipo;
16. valida conflictos, recursos inexistentes e historial;
17. limpia los datos creados.

Resultado esperado:

```text
Todas las pruebas integradas finalizaron correctamente.
```

## Datos para la demo

El script `seed-demo-data.sh` crea un conjunto coherente de flotas, maquinaria y solicitudes para evitar que la demo dependa del orden de pruebas.

```bash
chmod +x seed-demo-data.sh
./seed-demo-data.sh
```

Antes de una presentación conviene comprobar:

```bash
curl 'http://localhost:3000/api/v1/equipments?page=1&pageSize=100&status=AVAILABLE' | jq
curl 'http://localhost:3001/api/v1/requests?page=1&pageSize=100' | jq
```

Si no existen equipos `AVAILABLE`, las recomendaciones estarán vacías por diseño. Completar o cancelar una asignación activa libera su equipo.

## Observabilidad

Los servicios incluyen logging estructurado y soporte para OpenTelemetry.

En local se recomienda mantener la instrumentación activa sin usar el exporter `stdout`, porque imprime cada span y llena los logs. Las opciones adecuadas son:

- exporter deshabilitado en local;
- OTLP hacia un collector local si se necesita inspección;
- OTLP o el backend definido para GCP en ambientes cloud.

La selección debe realizarse mediante variables de ambiente, sin retirar los spans del código. De esta forma el mismo binario conserva la instrumentación en todos los ambientes.

Comandos útiles:

```bash
docker compose logs -f fleet-service logistic-service entropy-mcp-server n8n
docker compose ps
```

## Arquitectura objetivo en GCP

La arquitectura local no implica que todos los componentes deban publicarse en Internet.

```mermaid
flowchart TD
    LB["HTTPS Load Balancer"] --> FE["Next.js · Cloud Run"]
    FE --> N8N["n8n privado · VM"]
    N8N --> MCP["MCP privado en GKE"]
    FE --> LS["Logistic Service · Cloud Run"]
    LS --> FS["Fleet Service · Cloud Run"]
    FE --> FS["Fleet Service · Cloud Run"]
    LS --> MCP["Entropy MCP Server · Cloud Run"]
    LS --> SQL[("Cloud SQL PostgreSQL + pgvector")]
    FS --> SQL[("Cloud SQL PostgreSQL + pgvector")]
    LS --> V["Vertex AI"]

```

Propuesta de despliegue:

- Frontend Next.js, `fleet-service`, `logistic-service` y MCP en Cloud Run.
- PostgreSQL administrado en Cloud SQL para el MVP cloud.
- Vertex AI como proveedor de embeddings.
- n8n en una VM sin IP pública, con disco persistente.
- DNS privado para nombres internos.
- Conectividad desde Cloud Run hacia la VPC mediante Direct VPC egress o un conector compatible con el diseño de red.
- Secret Manager para contraseñas, tokens y API keys.
- HTTPS Load Balancer como entrada pública controlada.

No se recomienda exponer directamente n8n, PostgreSQL ni MCP. El acceso debe limitarse por red, identidad y autenticación de aplicación.

## Desarrollo con submódulos

### Actualizar todo

```bash
git submodule sync --recursive
git submodule update --init --recursive
git pull --recurse-submodules
```

### Trabajar en un servicio

Ejemplo con Logistics:

```bash
cd logistic-service
git switch develop
git pull

# realizar cambios y pruebas
git add .
git commit -m 'feat: describe el cambio'
git push
```

Luego se registra el nuevo puntero en el repositorio padre:

```bash
cd ..
git add logistic-service
git commit -m 'chore: update logistic-service submodule'
git push
```

El mismo proceso aplica a `fleet-service` y `entropy-mcp-server`.

### Si aparece una versión antigua

```bash
git submodule update --init --recursive --remote
git -C logistic-service status
git status
```

Antes de usar `--remote`, confirmar que `.gitmodules` defina la rama esperada. El repositorio padre siempre reproduce el commit fijado, no necesariamente el último commit visible en GitHub.

## Comandos útiles

```bash
# Construir y levantar
docker compose up -d --build

# Reconstruir un servicio
docker compose up -d --build logistic-service

# Reiniciar
docker compose restart fleet-service

# Ver estado
docker compose ps

# Detener sin borrar datos
docker compose down

# Reinicializar todo, incluidos PostgreSQL, Ollama y n8n
docker compose down -v
docker compose up -d --build
```

> `docker compose down -v` elimina los volúmenes locales. Se perderán bases, credenciales/configuración de n8n y modelos descargados de Ollama.

## Solución de problemas

### Logistics devuelve `502 fleet_service_unavailable`

Comprobar:

```bash
curl http://localhost:3000/health
docker compose logs fleet-service logistic-service
```

Dentro de Compose, la URL correcta es:

```text
http://fleet-service:3000
```

No debe usarse `localhost`, porque dentro del contenedor apuntaría al propio Logistics.

### Fleet responde `404 page not found` desde Logistics

Comprobar que `FLEET_SERVICE_URL` no incluya un prefijo `/api/v1` duplicado y que la ruta construida por el cliente coincida con la ruta real de Fleet.

### Recomendaciones vacías

Verificar que exista al menos un equipo que cumpla simultáneamente:

```text
status = AVAILABLE
type = equipmentType solicitado
nextMaintenanceHours - engineHours > 0
```

### El listado de assignments devuelve `data: null` aunque `total > 0`

Después de construir la consulta de GORM, se debe ejecutarla:

```go
result := query.
    Order("created_at DESC").
    Limit(pageSize).
    Offset(offset).
    Find(&assignments)
```

Omitir `Find(&assignments)` deja el slice sin cargar.

### Error `missing FROM-clause entry for table requests`

La tabla real es `logistics_requests`. No se deben seleccionar columnas con el alias `requests` si el `FROM` no declaró dicho alias. Usar columnas sin prefijo o declarar explícitamente:

```sql
FROM logistics_requests AS requests
```

### Error de validación de `Location.Name`

El cuerpo debe enviar el objeto anidado completo:

```json
{
  "location": {
    "name": "San Miguel",
    "latitude": 13.4833,
    "longitude": -88.1833
  }
}
```

### Gemini rechaza una tool con `exclusiveMinimum` o `type` como lista

Revisar los schemas publicados por MCP. Deben usar el subconjunto simple descrito en [Compatibilidad del schema con Gemini](#compatibilidad-del-schema-con-gemini). Después de cambiarlo, reconstruir MCP y refrescar las tools en n8n.

### No hay resultados semánticos

Comprobar:

```bash
curl http://localhost:11434/api/tags | jq
docker compose logs logistic-service ollama
```

También verificar que:

- el modelo configurado esté descargado;
- el vector tenga 768 dimensiones;
- existan embeddings para el mismo `provider` y `model` usados en la consulta;
- las solicitudes antiguas hayan sido reindexadas.

### PostgreSQL no reconoce el tipo `vector`

El contenedor debe usar una imagen con `pgvector`, por ejemplo `pgvector/pgvector:pg17`, y la base debe habilitar:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### El submódulo Logistics no existe o apunta a un worktree inválido

Primero comprobar que no haya cambios locales sin commit:

```bash
git -C logistic-service status
```

Si el directorio no existe o la metadata quedó inconsistente, desinicializarlo y guardar una copia de la metadata antes de recrearlo:

```bash
git submodule deinit -f -- logistic-service
mv .git/modules/logistic-service .git/modules/logistic-service.backup
git submodule sync --recursive
git submodule update --init --recursive logistic-service
```

Cuando el submódulo vuelva a funcionar y se haya verificado que la copia no contiene trabajo pendiente, la carpeta `.git/modules/logistic-service.backup` puede retirarse manualmente.

## Seguridad

- No guardar API keys ni contraseñas reales en Git.
- Restringir la API key de Google Maps a las APIs necesarias y, cuando aplique, a las IPs o identidades del backend que la utiliza.
- No ejecutar herramientas MCP de mutación sin confirmación.
- Aplicar autorización por rol antes de habilitar operaciones administrativas en producción.
- Mantener MCP, n8n y las bases en red privada.
- Utilizar cuentas de servicio con permisos mínimos en GCP.
- Registrar quién realizó cada cambio de estado o asignación cuando se incorpore autenticación de usuarios.

## Limitaciones del MVP

- La coordinación Fleet–Logistics usa llamadas HTTP síncronas y todavía no implementa saga, outbox ni reconciliación automática.
- No existe autenticación completa de usuarios y RBAC de extremo a extremo.
- No hay telemetría IoT real; los datos de uso y combustible son administrados o simulados.
- El cálculo de distancia es geográfico; aún no considera rutas, tráfico, peajes ni capacidad real del transporte.
- El frontend Next.js continúa pendiente.
- n8n complementa el producto, pero no debe convertirse en la fuente de verdad operativa.
- Las búsquedas vectoriales requieren reindexación cuando cambia el modelo.
- `QUERY` debe verificarse con la infraestructura de red elegida.

## Documentación por servicio

Para DTOs, validaciones, modelos internos y decisiones específicas consultar también:

```text
fleet-service/README.md
logistic-service/README.md
entropy-mcp-server/README.md
```

Este documento describe la integración completa y el estado funcional del MVP.
