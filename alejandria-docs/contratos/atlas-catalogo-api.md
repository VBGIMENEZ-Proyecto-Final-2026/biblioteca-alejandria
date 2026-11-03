# Contrato de atlas-catalogo con sus consumidores

**Versión 1 · 2026-11-02.** Este contrato describe lo que `atlas-catalogo` ofrece a `cronos-turnos` y a `hermes-app`: operaciones, DTO, autenticación y errores. Lo que no está acá no es parte del contrato y puede cambiar. Los ejemplos son respuestas reales del servicio corriendo en contenedores, con datos ficticios de la cátedra.

## 1. Alcance y reglas

- **Qué es:** una API de **solo lectura** sobre la copia local del catálogo (categorías, profesionales y horarios semanales). Nunca consulta a la cátedra al responder: lo que devuelve es lo último que se sincronizó.
- **Quién la consume:**
  - `hermes-app` para buscar y mostrar profesionales.
  - `cronos-turnos` para obtener los horarios vigentes de un profesional antes de armar la disponibilidad o iniciar una reserva (enunciado, sección 4.2).
- **Qué no se permite** (enunciado, sección 3): acceder a la base de atlas, a sus repositorios o a su código; y **copiar el catálogo en cronos** para buscar o reservar. Cronos pide cada vez, y a lo sumo guarda en una reserva datos descriptivos históricos del profesional.
- **Base:** `http(s)://<host-de-atlas>:8080`. Todas las rutas empiezan con `/api`, salvo la de salud. Formato `application/json`, UTF-8.
- **Solo `GET`.** Cualquier otro método responde `403`.

## 2. Autenticación y autorización

atlas **no emite ni guarda usuarios**: valida los JWT que emite `cronos-turnos` (decisión: [ADR 0004](../arquitectura/adr/0004-autenticacion-entre-servicios.md), opción A, se propaga el JWT del usuario).

### 2.1 Cómo llamar

```http
GET /api/professionals/207 HTTP/1.1
Authorization: Bearer <JWT del usuario, tal cual lo emitió cronos-turnos>
```

Cuando cronos llama a atlas en nombre de un usuario, **reenvía el mismo JWT que recibió del cliente**, sin modificarlo ni firmar uno nuevo. Así la identidad del usuario llega intacta y atlas puede dejarla en su log.

### 2.2 Qué debe cumplir el token

| Requisito | Detalle |
|---|---|
| Algoritmo | `RS256`. Se rechazan `HS256`, `none` y cualquier otro. |
| Firma | Verificada con la **clave pública** de cronos. atlas no tiene la clave privada ni puede forjar tokens. |
| `sub` | Obligatorio y no vacío (el `login` del usuario). |
| `exp` | Obligatorio. Vencido = rechazado. Se tolera un desfase de reloj de 60 s (`ATLAS_JWT_CLOCK_SKEW`). |
| `nbf` | Si está, se respeta (con la misma tolerancia). |
| `auth` | Autoridades separadas por espacio (`"ROLE_USER ROLE_ADMIN"`) o lista, como el claim de JHipster. Ya traen el prefijo `ROLE_`. El nombre del claim se cambia con `ATLAS_JWT_AUTHORITIES_CLAIM`. |

No se valida `iss` ni `aud` (limitación conocida, ver [seguridad](../arquitectura/seguridad-atlas-catalogo.md)). Ninguna decisión depende de un identificador que envíe el cliente: todo sale del token firmado.

### 2.3 Permisos por ruta

| Ruta | Acceso |
|---|---|
| `GET /actuator/health` | Público, sin detalles. |
| `GET /api/professionals`, `GET /api/professionals/{id}`, `GET /api/categories` | `ROLE_USER` o `ROLE_ADMIN`. |
| `GET /api/sync/status` | `ROLE_ADMIN`. |
| Todo lo demás (otros métodos, rutas inexistentes) | Denegado: `401` sin token, `403` con uno válido. |

Una ruta inexistente responde `403` y no `404`: la denegación se evalúa antes de saber si la ruta existe, para no revelar qué rutas hay.

## 3. Operaciones

### 3.1 `GET /api/professionals` · buscar profesionales

Devuelve una página de profesionales. Todos los parámetros son opcionales y se combinan con "y".

| Parámetro | Tipo | Efecto |
|---|---|---|
| `categoryId` | entero | Profesionales de esa categoría. |
| `name` | texto, hasta 100 caracteres | Texto contenido en "nombre apellido", sin distinguir mayúsculas. No ignora tildes. Los comodines `%` y `_` se tratan como texto. Se recortan los espacios; vacío equivale a no enviarlo. |
| `enabled` | `true` / `false` | Estado habilitado del profesional (filtro literal). |
| `available` | `true` / `false` | `true`: el profesional atiende (profesional y categoría habilitados y al menos un horario semanal habilitado). `false`: los que no. Independiente de `enabled`. |
| `dayOfWeek` | `MONDAY` … `SUNDAY` | Refina `available` a un día. **Requiere `available`.** |
| `page` | entero ≥ 0 | Página, desde 0. Por defecto `0`. |
| `size` | entero 1 a 100 | Tamaño de página. Por defecto `20`. |

El orden es fijo (apellido, nombre, ID): el cliente no elige columnas.

> **"Disponible" significa que el profesional atiende, no que le queden turnos libres.** Los turnos libres dependen de las ocupaciones de la cátedra y los resuelve `cronos-turnos` (enunciado, sección 7).

**Respuesta `200`** (`PageResult<ProfessionalSummary>`):

```json
{
  "content": [
    { "id": 218, "firstName": "Romina", "lastName": "Acosta", "enabled": true,
      "category": { "id": 107, "name": "Ginecologia", "enabled": true } },
    { "id": 207, "firstName": "Diego", "lastName": "Alvarez", "enabled": true,
      "category": { "id": 103, "name": "Clinica medica", "enabled": true } }
  ],
  "page": 0, "size": 2, "totalElements": 24, "totalPages": 12
}
```

### 3.2 `GET /api/professionals/{id}` · detalle con horarios

Devuelve el profesional con **todos** sus horarios semanales (habilitados o no, cada uno con su estado), ordenados por día y hora de inicio. También devuelve a un profesional deshabilitado, con `enabled: false`: el consumidor decide qué hacer con él, y lo esperable es **no ofrecer turnos** de un profesional o un horario deshabilitado.

**Respuesta `200`** (`ProfessionalDetail`):

```json
{
  "id": 207, "firstName": "Diego", "lastName": "Alvarez", "enabled": true,
  "category": { "id": 103, "name": "Clinica medica", "enabled": true },
  "schedules": [
    { "id": 311, "dayOfWeek": "MONDAY", "startTime": "18:00:00", "endTime": "21:00:00",
      "slotDurationMinutes": 30, "enabled": true },
    { "id": 312, "dayOfWeek": "WEDNESDAY", "startTime": "12:00:00", "endTime": "15:00:00",
      "slotDurationMinutes": 30, "enabled": true }
  ]
}
```

Esta es **la operación que usa cronos** para construir la disponibilidad: de cada horario habilitado sale la grilla de turnos del día (de `startTime` a `endTime`, cada `slotDurationMinutes`), a la que cronos le resta las ocupaciones que informa la cátedra.

### 3.3 `GET /api/categories` · categorías

Lista de categorías ordenadas por nombre, para elegir una al filtrar. Parámetro opcional `enabled` (`true` / `false`).

```json
[ { "id": 101, "name": "Cardiologia", "enabled": true },
  { "id": 103, "name": "Clinica medica", "enabled": true } ]
```

Una lista vacía (`[]`, `200`) es una respuesta válida, por ejemplo con `enabled=false` cuando todas están habilitadas.

### 3.4 `GET /api/sync/status` · estado de la sincronización (administración)

Solo `ROLE_ADMIN`. Informa de dónde viene lo que atlas responde. Los campos sin valor van como `null`, nunca se omiten. Las fechas son ISO-8601 en UTC.

```json
{ "localVersion": 1, "status": "IDLE", "lastResult": "NOOP",
  "lastSnapshotReason": "BASE_VACIA", "lastSyncAt": "2026-11-03T00:19:16.890321Z",
  "lastError": null }
```

Con una falla, `lastError` trae `{ "code", "message", "at" }`. `status` es `IDLE` o `ERROR` (`RUNNING` existe en el modelo pero nunca se informa: mientras una corrida está abierta nadie ve su cambio); `lastResult`, `NOOP`, `INCREMENTAL` o `SNAPSHOT`; `lastSnapshotReason`, `BASE_VACIA`, `NO_VERIFICABLE`, `LOCAL_ADELANTADA`, `FUERA_DE_VENTANA` o `FALTA_VERSION` (el motivo del último snapshot). Un usuario común recibe `403`: el estado muestra errores internos.

### 3.5 `GET /actuator/health` · salud

Público. `{"groups":["liveness","readiness"],"status":"UP"}`. Cronos puede usarlo para saber si atlas está en pie, no si el catálogo está al día.

## 4. Tipos (DTO)

| Tipo | Campos |
|---|---|
| `CategoryView` | `id` (entero), `name` (texto), `enabled` (booleano) |
| `ProfessionalSummary` | `id`, `firstName`, `lastName`, `enabled`, `category` (`CategoryView`) |
| `ScheduleView` | `id`, `dayOfWeek` (`MONDAY` … `SUNDAY`), `startTime` y `endTime` (`HH:mm:ss`, hora local del consultorio, sin zona), `slotDurationMinutes` (entero), `enabled` |
| `ProfessionalDetail` | `id`, `firstName`, `lastName`, `enabled`, `category`, `schedules` (lista de `ScheduleView`) |
| `PageResult<T>` | `content` (lista de `T`), `page`, `size`, `totalElements`, `totalPages` |

Los identificadores son los de la cátedra (no los genera atlas). El contrato no expone el formato interno de `Page` de Spring Data.

## 5. Errores

Todos los errores son `application/problem+json` con la forma del anexo de integración de la cátedra (sección 13). Los mensajes son fijos: **no repiten el valor recibido ni la causa técnica**, que va solo al log.

```json
{ "title": "Not Found", "status": 404, "detail": "No existe el profesional pedido",
  "message": "error.http.404", "path": "/api/professionals/999999",
  "code": "PROFESIONAL_NO_ENCONTRADO" }
```

El consumidor debe decidir por **`code`**, no por el texto de `detail`.

| HTTP | `code` | Cuándo | Qué hace el consumidor |
|---|---|---|---|
| `400` | `BUSQUEDA_INVALIDA` | `page` < 0; `size` fuera de 1 a 100; `name` de más de 100 caracteres; `dayOfWeek` sin `available`; un parámetro con tipo inválido (`categoryId=abc`, `dayOfWeek=LUNES`) | Es un error del cliente: corregir y no reintentar. |
| `401` | `NO_AUTENTICADO` | Sin token, o token inválido, vencido, mal firmado, con otro algoritmo o sin `sub`/`exp`. Lleva `WWW-Authenticate: Bearer`. No dice cuál fue el motivo. | Pedir un token nuevo al usuario (volver a iniciar sesión). |
| `403` | `SIN_PERMISO` | Token válido sin el rol necesario; método no permitido; ruta inexistente. | No reintentar: no mejora. |
| `404` | `PROFESIONAL_NO_ENCONTRADO` | El ID no existe en la copia local. | Tratar la referencia como inexistente (enunciado, sección 8: "referencias inexistentes"). |
| `503` | `CATALOGO_NO_DISPONIBLE` | La base de atlas no responde. | **No iniciar operaciones que necesiten validar información vigente** (sección 8 del enunciado). Reintentar con espera y límite. |

Si atlas está caído o no contesta (error de red o timeout, sin cuerpo), vale lo mismo que para el `503`.

## 6. Garantías y límites

- **Lectura consistente:** una respuesta refleja una versión del catálogo completa. La sincronización aplica un snapshot en una sola transacción y los cambios incrementales de a una versión, así que no se ve una copia a medias.
- **Puede estar desfasada:** si la cátedra publicó una versión y atlas aún no la aplicó, atlas responde la anterior. El desfase normal es de segundos (aviso por Kafka) y, si el aviso se pierde, de hasta 60 s (verificación periódica). `GET /api/sync/status` lo muestra.
- **Las bajas no borran:** un profesional, categoría u horario que la cátedra da de baja pasa a `enabled: false` y sigue consultable por ID. Por eso un ID viejo no da `404` sino `enabled: false`.
- **Sin escritura ni paginación de horarios:** el detalle trae todos los horarios del profesional en una respuesta.
- **Sin réplica en el consumidor:** cronos no debe guardar el catálogo (ver sección 1); pide cada vez que lo necesita.
- **Timeouts sugeridos para el consumidor:** conexión 3 s, lectura 10 s (la consulta es local a la base de atlas), con a lo sumo 2 reintentos con espera creciente solo ante `503` o error de red. No reintentar `4xx`.
- **Transporte:** por defecto HTTP en la red local. HTTPS se activa por configuración (ver el README de atlas, "Seguridad"). Un consumidor que salga de la máquina local **debe** usar HTTPS, porque el token viaja en la cabecera.
- **CORS:** solo los orígenes de `ATLAS_CORS_ALLOWED_ORIGINS`, solo `GET` y `OPTIONS`, sin credenciales. La app Android no es un navegador y no lo necesita.

## 7. Evolución del contrato

- Agregar un campo opcional a una respuesta, o un filtro opcional, **no** rompe el contrato: el consumidor debe ignorar los campos que no conoce.
- Quitar o renombrar un campo, cambiar su tipo o un `code` de error, o cambiar los permisos de una ruta, **sí** lo rompe y exige acordarlo con los consumidores.
- Hoy no hay versión en la ruta (`/api/v1`): es una sola versión. Si hiciera falta romper el contrato, se agregaría una ruta versionada y se mantendría la anterior hasta migrar.

## 8. Cómo se verifica

| Qué | Dónde |
|---|---|
| Parámetros, JSON y errores `400`/`404`/`503` | `ProfessionalsControllerTest`, `ProfessionalSearchCriteriaTest` |
| Cada filtro, sus combinaciones, orden y paginación contra PostgreSQL real | `BusquedaProfesionalesTest`, `DisponibilidadTest` |
| `401`/`403`, algoritmos y tokens inválidos, rutas desconocidas denegadas | `SeguridadApiTest` |
| CORS | `CorsApiTest`, `CorsPorDefectoTest` |
| Estado de la sincronización | `EstadoSincronizacionTest`, `SyncStatusControllerTest` |
| Con la aplicación real en contenedores | [`evidencias/isla-1-contenedores.md`](../evidencias/isla-1-contenedores.md) |

Ejemplo de uso con un token de desarrollo:

```bash
TOKEN=$(scripts/dev-token.sh ~/.atlas-dev/dev-private.pem ana ROLE_USER)
curl -H "Authorization: Bearer $TOKEN" 'localhost:8080/api/professionals?name=alv&categoryId=103&available=true&dayOfWeek=MONDAY'
curl -H "Authorization: Bearer $TOKEN" localhost:8080/api/professionals/207
```

## 9. Lo que cronos debe cumplir de su lado

Para que el contrato funcione, `cronos-turnos` tiene que:

1. emitir JWT `RS256` con `sub` y `auth` (y `exp`), y publicar su **clave pública** para atlas (hoy, `ATLAS_JWT_PUBLIC_KEY_LOCATION`);
2. reenviar el token del usuario al llamar a atlas (ADR 0004);
3. no guardar una réplica del catálogo;
4. tratar `503` o la falta de respuesta como "no iniciar la operación" y `404` como "referencia inexistente".

Los claims exactos que cronos va a emitir están sin confirmar hasta que exista el esqueleto de cronos (issue #33 de atlas); si cambian, se actualiza la sección 2.2.
