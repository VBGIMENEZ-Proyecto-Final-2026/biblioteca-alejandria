# Contrato de cronos-turnos: usuarios y autenticación

**Versión 1 (parcial) · 2026-11-21.** Lo que `cronos-turnos` ofrece hoy a `hermes-app`: registro, inicio de sesión, emisión del JWT, consulta de la propia cuenta y disponibilidad de turnos e inicio de reservas. Consulta, cancelación y Kafka todavía no existen y se agregan a este contrato cuando se implementen. Lo que no está acá no es parte del contrato.

## 1. Alcance y reglas

- **Quién emite los tokens:** cronos-turnos (decisión del 2026-11-01, [ADR 0004](../arquitectura/adr/0004-autenticacion-entre-servicios.md)). Atlas solo los valida con la clave pública.
- **Sin JHipster:** el servicio implementa los usuarios con Spring Security y un contrato compatible con el usuario de JHipster, como pide el enunciado 3.2 ([ADR 0005](../arquitectura/adr/0005-usuarios-y-jwt-en-cronos-sin-jhipster.md)).
- **Base:** `http(s)://<host-de-cronos>:8081`. Formato `application/json`, UTF-8. Los errores son `application/problem+json`.
- **Rutas públicas:** `POST /api/register`, `POST /api/authenticate` y `GET /actuator/health`. Ignoran el encabezado `Authorization`: un token vencido guardado no impide volver a iniciar sesión. `GET /api/account`, `GET /api/professionals/{id}/availability` y `POST /api/reservations` piden token. Todo lo demás se deniega.
- **No es la cuenta técnica de la cátedra.** Un usuario final y la cuenta técnica de integración son identidades distintas (enunciado 3.2): el JWT de la cátedra nunca se expone a la app.

## 2. Registro: `POST /api/register`

Sin autenticación. Cuerpo:

| Campo | Obligatorio | Regla |
|---|---|---|
| `login` | sí | 3 a 50; letras, números y `. _ @ -`. Se guarda en minúsculas y es único aunque cambien las mayúsculas. |
| `password` | sí | 4 a 100 caracteres. Se guarda con hash, nunca en claro. |
| `firstName`, `lastName` | no | Hasta 50. |
| `email` | no | Válido, 5 a 254. Se guarda en minúsculas. Único si se informa. |
| `imageUrl` | no | Hasta 256. |
| `langKey` | no | 2 a 10. Por defecto `es`. |

Cualquier otro campo (`id`, `activated`, `authorities`, fechas) **se ignora**: los decide el backend.

Respuesta `201 Created`, sin contraseña ni hash:

```json
{
  "id": 1,
  "login": "juan.perez",
  "firstName": "Juan",
  "lastName": null,
  "email": "juan@ejemplo.test",
  "imageUrl": null,
  "langKey": "es",
  "activated": true,
  "authorities": ["ROLE_USER"]
}
```

El usuario queda **activo** de inmediato y puede iniciar sesión sin verificar el correo (enunciado 3.2).

## 3. Inicio de sesión: `POST /api/authenticate`

Sin autenticación. Misma forma que el login de la cátedra (referencia de integración, 5.2):

```json
{ "username": "juan.perez", "password": "una-clave", "rememberMe": false }
```

| Campo | Regla |
|---|---|
| `username` | 1 a 254. No distingue mayúsculas. |
| `password` | 4 a 100. |
| `rememberMe` | Opcional. `true` pide la vigencia larga. |

Respuesta `200 OK`: `{ "id_token": "<jwt>" }`. El mismo token va en el encabezado `Authorization: Bearer <jwt>`.

### 3.1 El token

JWT firmado con **RS256**. Claims:

| Claim | Valor |
|---|---|
| `sub` | El `login` del usuario, en minúsculas. |
| `auth` | Las autoridades separadas por espacio, ordenadas (por ejemplo `ROLE_USER`). Es el claim que atlas lee, el mismo que usa JHipster. |
| `iat` | Momento de emisión. |
| `exp` | Vencimiento: 1 hora, o 30 días con `rememberMe` (configurable por `CRONOS_JWT_TTL` y `CRONOS_JWT_REMEMBER_ME_TTL`). |

No lleva email, nombres ni nada de la contraseña. No hay `iss`, `aud` ni `kid`. No hay refresco ni revocación: un token vale hasta que vence.

## 4. Cuenta propia: `GET /api/account`

Requiere `Authorization: Bearer <jwt>` con `ROLE_USER` o `ROLE_ADMIN`. No recibe ningún parámetro: el usuario sale del `sub` del token ya validado, así que nadie puede pedir la cuenta de otro (un `?login=` o un `?id=` se ignora). Respuesta `200 OK` con la misma forma que el registro, sin contraseña ni hash. Si el usuario del token ya no existe o no está activo, `401`.

### 4.1 Qué valida cronos de un token

Solo RS256 (un token `HS256` o `none` se rechaza), la firma, el vencimiento con una tolerancia de reloj de 60 segundos y los claims `sub` y `exp` obligatorios. Las autoridades salen del claim `auth`. Un cambio de rol en la base no se ve en un token ya emitido hasta que vence.

### 4.2 CORS

Sin orígenes configurados no se acepta ninguno. Con una lista (`esquema://host[:puerto]`, sin comodines) se aceptan solo esos, con `GET`, `POST` y `OPTIONS`, los encabezados `Authorization`, `Content-Type` y `Accept`, y sin credenciales. La app Android no es un navegador y no lo necesita.

## 5. Disponibilidad: `GET /api/professionals/{professionalId}/availability`

Requiere `Authorization: Bearer <jwt>` con `ROLE_USER` o `ROLE_ADMIN`. Devuelve los turnos libres de un profesional entre dos fechas. Es la operación con la que la app muestra qué se puede reservar (enunciado 4.2 y 7).

| Parámetro | Obligatorio | Regla |
|---|---|---|
| `professionalId` (ruta) | sí | Entero. Es el id del profesional **en el catálogo** (atlas). |
| `from`, `to` | sí | `yyyy-MM-dd`, ambos inclusivos. `from` no puede ser posterior a `to` y el rango no puede superar 31 días (`CRONOS_AVAILABILITY_MAX_RANGE_DAYS`). |

Respuesta `200 OK`:

```json
{
  "professionalId": 207,
  "from": "2026-11-23",
  "to": "2026-11-25",
  "slots": [
    { "date": "2026-11-23", "startTime": "18:00:00", "endTime": "18:30:00" },
    { "date": "2026-11-23", "startTime": "19:30:00", "endTime": "20:00:00" }
  ]
}
```

Los turnos salen ordenados por fecha y hora. Una lista vacía es una respuesta válida.

### 5.1 Cómo se calcula

1. Cronos pide a atlas `GET /api/professionals/{id}` **reenviando el mismo JWT del usuario**, sin modificarlo ([ADR 0004](../arquitectura/adr/0004-autenticacion-entre-servicios.md)). Si atlas falla, cronos no consulta a la cátedra.
2. De cada horario semanal **habilitado** sale la grilla del día (de `startTime` a `endTime`, cada `slotDurationMinutes`); solo cuentan los turnos que entran completos. Un profesional o un horario deshabilitado no ofrece turnos. Si el profesional no atiende en el rango, se responde vacío sin consultar a la cátedra.
3. Cronos pide **una sola vez** a la cátedra las ocupaciones de todo el rango (`GET /api/appointment-occupancies`, con el JWT técnico del proyecto, referencia de integración 8) y descarta los turnos `CONFIRMED` y `HELD`. Un turno se identifica por fecha y hora de inicio.
4. Se descartan los turnos que **ya empezaron**, comparando en la hora local del consultorio (`CRONOS_CLINIC_ZONE`, por defecto `America/Argentina/Buenos_Aires`): los horarios y las ocupaciones no traen zona.

Cronos **no guarda** el catálogo ni las ocupaciones: cada consulta las pide de nuevo (enunciado 3). La respuesta no incluye datos del profesional, solo los turnos.

### 5.2 Fallas y límites

- **Timeouts y reintentos acotados.** Atlas: 2 s para conectar, 5 s para leer, 1 reintento. Cátedra: 3 s, 10 s, 1 reintento. Solo se reintentan lecturas y solo fallas transitorias (red, timeout y `503`). Máximo 5 reintentos por configuración.
- **No se siguen redirecciones**: un token nunca se reenvía a otro destino. Ningún token se registra en un log ni en un mensaje de error.
- **Una foto, no una reserva.** Entre que se consulta y se pide un hold otro usuario puede tomar el turno; el hold (próxima etapa) es lo que lo reserva y la cátedra responde `SLOT_ALREADY_HELD` o `SLOT_ALREADY_RESERVED`.
- Atlas responde con su copia local: si no sincronizó con la cátedra, los horarios pueden estar desactualizados.
- Un estado de ocupación que cronos no conoce hace fallar la consulta (`503`): es mejor que ofrecer un turno que podría estar tomado.

## 6. Reservas: `POST /api/reservations`

Requiere `Authorization: Bearer <jwt>` con `ROLE_USER` o `ROLE_ADMIN`. Inicia una reserva (enunciado 7): valida el turno contra atlas, pide un hold a la cátedra y lo confirma inicialmente. El proceso queda **asociado al usuario del token**, esperando la información adicional (el teléfono y el resultado final llegan por Kafka, issue #15).

```json
{ "professionalId": 218, "date": "2026-12-15", "startTime": "14:30",
  "patientFirstName": "Juan", "patientLastName": "Pérez" }
```

| Campo | Regla |
|---|---|
| `professionalId`, `date`, `startTime` | Obligatorios. El turno tiene que existir en la agenda vigente del profesional y no haber empezado. |
| `patientFirstName`, `patientLastName` | Obligatorios, 2 a 100 caracteres. |

Cualquier otro campo (`id`, `status`, `userId`, `externalPatientId`, `holdId`...) **se ignora**. El dueño es el del token; la cátedra conoce al paciente como `user-<id>`, un identificador opaco.

Respuesta `202 Accepted` (el proceso sigue):

```json
{ "id": 6, "status": "WAITING_FOR_PHONE", "professionalId": 218,
  "professionalFirstName": "Romina", "professionalLastName": "Acosta",
  "date": "2026-12-15", "startTime": "14:30:00", "endTime": "15:00:00",
  "patientFirstName": "Juan", "patientLastName": "Pérez",
  "expiresAt": "2026-12-15T14:44:50Z", "phoneSubmitted": false, "createdAt": "2026-11-21T16:43:08.189582Z" }
```

`phoneSubmitted` dice si ya se mandó el teléfono a la cátedra (el número no se guarda ni se devuelve). El `id` es el de cronos. La respuesta **no expone** el `holdId` ni el `reservationProcessId` de la cátedra ni el usuario.

### 6.1 Cómo se evita perder o duplicar

- **El mismo pedido dos veces devuelve el mismo proceso** y no crea otro hold (la base lo impide con un índice único parcial, también ante dos pedidos simultáneos).
- **Si no se sabe si el hold se creó** (la cátedra no respondió), el proceso se cierra como `FAILED` (`CATEDRA_UNAVAILABLE`) y el hold, si existe, vence solo. Los holds no se reintentan solos: tienen efectos.
- **Si no se sabe si se confirmó**, se reconcilia una vez (repetir la confirmación es seguro) y, si sigue sin saberse, queda en `HELD`: repetir el pedido **retoma la confirmación** sin crear otro hold.
- **Un proceso que ya venció se cierra al volver a pedir el turno:** si el proceso activo (`HELD` o `WAITING_FOR_PHONE`) ya pasó su `expiresAt`, se cierra como `EXPIRED` y se empieza uno nuevo. Una reserva `CONFIRMED` no vence.
- Un estado final nunca retrocede.

### 6.2 Responder el pedido de teléfono: `POST /api/reservations/{id}/phone`

Requiere `Authorization: Bearer <jwt>` con `ROLE_USER` o `ROLE_ADMIN`. Es el paso 5 del flujo del enunciado (sección 7): la cátedra pidió el teléfono por Kafka (`AdditionalInformationRequested`) y cronos lo envía (`AdditionalInformationSubmitted`, referencia 15.5).

```json
{ "phoneNumber": "+54 9 (261) 555-1234" }
```

Cronos **valida el formato como la cátedra** (referencia 15.5): quita espacios, guiones, paréntesis y puntos, y lo que queda tiene que cumplir `^\+?[0-9]{7,15}$`. Manda el número ya limpio. Cualquier otro campo del cuerpo se ignora: el dueño, el hold y el `requestEventId` son los del proceso.

Respuesta `202 Accepted`: el proceso sigue esperando. **El resultado (confirmada, teléfono rechazado, vencida) llega después por Kafka** y se ve en el `status` de la reserva; hasta entonces el `status` es `WAITING_FOR_PHONE` y `phoneSubmitted` es `true`.

**Qué se exige, en este orden:**

| Condición | Si no se cumple |
|---|---|
| La reserva existe y es del usuario del token | `404 RESERVATION_NOT_FOUND`, igual para una inexistente que para la de otro usuario (no se revela que existe) |
| La cátedra ya pidió el teléfono (llegó `AdditionalInformationRequested`) | `409 PHONE_NOT_REQUESTED`: se puede reintentar en unos segundos |
| El proceso sigue esperando el teléfono (`WAITING_FOR_PHONE`) | `409 RESERVATION_NOT_AWAITING_PHONE` (confirmada, vencida, inválida, cancelada o fallida) |
| No pasó su `expiresAt` | `409 RESERVATION_EXPIRED` (no se cambia el estado: lo cierra el evento de la cátedra) |
| No hay un teléfono enviado sin respuesta | `409 PHONE_ALREADY_SUBMITTED`: se libera cuando la cátedra rechaza el teléfono o pide otro |
| El formato es válido | `400 INVALID_PHONE_NUMBER` |
| Kafka confirma el envío a tiempo | `503 PHONE_DELIVERY_UNAVAILABLE`: no se marca nada y se puede reintentar |

**El teléfono es un dato personal y cronos no lo guarda ni lo registra** (decisión D3 del plan de Kafka). Se valida, se manda a la cátedra y se descarta. Lo único que se guarda es **cuándo** se mandó (`phone_submitted_at`). Ningún mensaje de error lo repite, ningún log lo escribe y ninguna tabla tiene una columna donde guardarlo (una prueba lo exige). Quien lo conserva es la cátedra, que lo devuelve como `patientPhone` en su listado de reservas.

**Qué garantiza el envío:** el productor usa `acks=all` e idempotencia, con un plazo acotado (5 s por defecto): pasado ese tiempo responde `503` y **no se reintenta solo**. La clave del mensaje es el `reservationProcessId` y cada envío lleva un `eventId` nuevo. Se manda primero y se marca después: si la marca no se puede guardar, el envío ya salió y igual se responde `202` (avisar un error haría reenviar el teléfono). La marca protege del doble envío pero no lo garantiza: dos pedidos exactamente simultáneos podrían mandar dos mensajes, que la cátedra distingue por su `eventId` y que cronos tolera (un resultado final no retrocede).

**Si la cátedra rechaza el teléfono** (`AdditionalInformationRejected`) el proceso **sigue** en `WAITING_FOR_PHONE` hasta su `expiresAt` (referencia 15.7) y se puede mandar otro.

### 6.3 Límites

- Todavía no hay listado, consulta ni cancelación de reservas (issue #12). Los resultados de la cátedra los aplica el consumidor de Kafka (issue #15); si cronos no estuvo escuchando, un proceso queda en `WAITING_FOR_PHONE` aunque la cátedra lo haya dado por vencido, hasta que se recupere al reiniciar (#13) o el usuario vuelva a pedir ese turno (se cierra como `EXPIRED`).
- Un proceso en `STARTING` o un hold huérfano se resuelven con la recuperación al reiniciar (issue #13); hasta entonces el pedido repetido recibe `409 RESERVATION_IN_PROGRESS`.

## 7. Errores

| Situación | HTTP | `code` |
|---|---|---|
| Falta un campo, formato o largo inválido, o JSON ilegible | 400 | `VALIDATION_ERROR` (con `fieldErrors` en los errores de campo) |
| En el registro, la contraseña presente fuera de 4 a 100 y nada más falla | 400 | `INVALID_PASSWORD` |
| Login ya usado | 400 | `USERNAME_ALREADY_EXISTS` |
| Email ya usado | 400 | `EMAIL_ALREADY_EXISTS` |
| Login inexistente, contraseña equivocada o usuario no activo | 401 | `INVALID_CREDENTIALS` (siempre el mismo cuerpo) |
| Sin token, token mal formado, vencido, alterado, de otra clave, de otro algoritmo o sin `exp`, o de un usuario que ya no existe o no está activo | 401 | `NO_AUTENTICADO` (con `WWW-Authenticate: Bearer`) |
| Token válido pero sin el rol que pide la ruta | 403 | `SIN_PERMISO` |
| Ruta o método no habilitados, con token válido | 403 | `SIN_PERMISO` |
| Ruta o método no habilitados, sin token | 401 | `NO_AUTENTICADO` |
| Disponibilidad: rango invertido o de más de 31 días | 400 | `INVALID_DATE_RANGE` |
| Disponibilidad: fecha mal formada, falta un parámetro o el id no es un número | 400 | `VALIDATION_ERROR` (nombra el parámetro, no repite el valor) |
| Disponibilidad: profesional que atlas no conoce | 404 | `PROFESSIONAL_NOT_FOUND` |
| Disponibilidad: atlas caído, lento o que rechaza el token | 503 | `CATALOG_UNAVAILABLE` |
| Disponibilidad: cátedra caída, lenta o que rechaza la credencial técnica | 503 | `CATEDRA_UNAVAILABLE` |
| Reservas: cuerpo inválido | 400 | `VALIDATION_ERROR` |
| Reservas: el turno no está en la agenda o ya empezó | 400 | `INVALID_SLOT` |
| Reservas: el profesional está deshabilitado | 400 | `PROFESSIONAL_DISABLED` |
| Reservas: turno ya tomado en la cátedra | 409 | `SLOT_ALREADY_HELD` o `SLOT_ALREADY_RESERVED` |
| Reservas: el hold venció antes de confirmarse | 409 | `HOLD_EXPIRED` |
| Reservas: el mismo pedido se está procesando ahora | 409 | `RESERVATION_IN_PROGRESS` |
| Reservas: la cátedra rechazó por un motivo que no debería ocurrir | 502 | `CATEDRA_ERROR` (sin detalle) |
| Teléfono: la reserva no existe o es de otro usuario | 404 | `RESERVATION_NOT_FOUND` (el mismo cuerpo para las dos) |
| Teléfono: formato inválido o falta | 400 | `INVALID_PHONE_NUMBER` (no repite el valor) |
| Teléfono: la cátedra todavía no lo pidió | 409 | `PHONE_NOT_REQUESTED` |
| Teléfono: la reserva ya no espera un teléfono | 409 | `RESERVATION_NOT_AWAITING_PHONE` |
| Teléfono: el proceso ya venció | 409 | `RESERVATION_EXPIRED` |
| Teléfono: ya se envió uno y la cátedra no respondió | 409 | `PHONE_ALREADY_SUBMITTED` |
| Teléfono: Kafka no confirmó el envío a tiempo (o el envío está apagado) | 503 | `PHONE_DELIVERY_UNAVAILABLE` |
| Base de datos no disponible | 503 | `SERVICE_UNAVAILABLE` |

Forma del error: `title`, `status`, `message`, `path` y `code`, como en la referencia de integración (sección 13). Los mensajes son fijos: **no repiten** el valor recibido, y menos una contraseña. El `401` y el `403` **no dicen por qué** falló el token y nunca lo repiten; sus códigos son los mismos que usa atlas.

Los vocabularios `VALIDATION_ERROR`, `USERNAME_ALREADY_EXISTS`, `EMAIL_ALREADY_EXISTS` e `INVALID_PASSWORD` salen de la matriz de errores de la cátedra para el registro de la cuenta técnica (13.1); el enunciado no define validaciones propias para el usuario final, así que se reutilizan como referencia.

## 8. Lo que todavía no está

- Cierre del issue #33 de atlas: la prueba cruzada ya se hizo (un token real de cronos fue aceptado por atlas, [evidencia](../evidencias/isla-2-prueba-cruzada.md)) y falta que el alumno lo cierre.
- Consulta y cancelación de reservas propias (la consulta del estado, `GET /api/reservations/{id}`, es el paso 6), recuperación al reiniciar y la corrida real contra la cátedra.
- Un usuario administrador (`ROLE_ADMIN`): el registro solo crea `ROLE_USER`.
- Recuperación de contraseña, edición del perfil, límite de intentos de login y revocación de tokens.
