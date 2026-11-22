# ADR 0006 · Norma de logs: un evento con código estable por línea, pares `clave=valor` y sin datos personales

**Estado:** aceptado por el alumno el 2026-11-22 e implementado en `cronos-turnos` (rama `feature/logs-explicitos`); **pendiente de aplicar en `atlas-catalogo`** (ver "Alcance") · **Componente:** cronos-turnos y atlas-catalogo · **Contexto:** antes de escribir el consumidor de Kafka de cronos (issue #15) · **Relacionado:** [ADR 0001](0001-configuracion-y-secretos.md), [ADR 0003](0003-arquitectura.md)

## Contexto

Los logs de cronos eran frases libres en español, casi todas `WARN` de fallas: *"La cátedra respondió HTTP 503 (code=X) al confirmar el hold"*. Tenían cuatro problemas:

- **No se podía buscar con precisión.** No había un código estable: cada frase se redactaba a mano, así que `grep` dependía de acordarse de las palabras exactas.
- **El camino feliz no dejaba rastro.** No se veía que un hold se había creado, que una reserva pasó a esperar el teléfono ni que alguien inició sesión. Para saber *qué había pasado* había que adivinarlo a partir de la base.
- **No se podía seguir un pedido.** Las líneas de un mismo pedido no compartían ningún identificador, y con Kafka (varios mensajes y reintentos) iba a ser peor.
- **Había un dato personal en un log.** El manejador del `403` escribía el nombre de usuario (`login`).

Con Kafka el problema crece: un consumidor trabaja sin pedido HTTP, descarta o estaciona mensajes y reintenta, y cada una de esas decisiones tiene que quedar dicha en el log. Esta norma se decide *antes* de escribir ese código para que nazca con ella.

## Decisión

Cada línea de log que informa algo (`INFO`, `WARN`, `ERROR`) es **un evento**: un código estable seguido de pares `clave=valor`, escrito siempre con una clase única (`LogEvent`).

```
evento=reserva.hold.confirmado usuario=17 reserva=16 proceso=process-a92b47d0 estado=WAITING_FOR_PHONE vence=2030-01-01T10:01:00Z siguiente=espera_el_telefono
```

Se apoya en prácticas conocidas: el formato **logfmt** (pares `clave=valor`, legible a ojo y fácil de buscar), las severidades de **RFC 5424** y el **OWASP Logging Cheat Sheet** (qué registrar, qué no, y la inyección de logs).

### 1. Forma de la línea

- Empieza con `evento=<código>`. El código tiene la forma `dominio.accion[.detalle]`, en minúsculas con guion bajo (`reserva.hold.creado`, `catedra.credencial.rechazada`). **Es el nombre del evento y no cambia**: se busca con `grep evento=reserva.hold`.
- Siguen pares `clave=valor`. Las claves son `[a-z0-9_]`. Un valor con espacio, `=`, comilla o barra va entre comillas; vacío se escribe `""`; ausente, `-`.
- **Una línea, un evento.** Los saltos de línea y los caracteres de control de un valor se escapan (`\n`, `\r`, `\t`, `\u00XX`). Un valor que viene de afuera (una URL, un encabezado, un campo del cuerpo) no puede fabricar una línea falsa: es la **inyección de logs** del OWASP.
- Cada valor se corta a 200 caracteres.

### 2. Niveles

| Nivel | Cuándo | Ejemplos |
|---|---|---|
| `ERROR` | Un bug, o algo que exige que alguien intervenga. **Único nivel con la traza completa**, una sola vez. | `catedra.rechazo_inesperado`, `http.pedido.fallido` |
| `WARN` | Una falla esperable que se manejó, o una degradación: la cátedra no responde, un reintento, un acceso rechazado. | `catedra.llamada.sin_respuesta`, `usuario.login.fallido` |
| `INFO` | Un **hito de negocio**: una línea por transición de estado, más una línea de cierre por pedido HTTP. | `reserva.hold.creado`, `usuario.registrado` |
| `DEBUG` | Detalle técnico. Lo único que se escribe con `log.debug` directo. | — |

Una falla se registra **una sola vez**, donde se maneja: no se registra y se relanza, porque duplica la línea y confunde cuál es la real.

### 3. Qué dice cada línea

Cada evento responde, con campos, a: **qué pasó** (el código), **a quién** (`usuario`, `reserva`, `proceso`, `hold`, `profesional`, ids y nunca nombres), **con qué resultado** (`estado`, `motivo`, `codigo`) y **qué se hizo después** (`accion=proceso_cerrado`, `accion=rotar_token_en_env`, `accion=queda_en_HELD_repetir_el_pedido_la_retoma`). Cuando se desconoce si una operación en la cátedra se aplicó, se dice (`resultado=se_desconoce_si_se_aplico`).

### 4. Seguimiento de un pedido

`RequestLogFilter` (primero en la cadena de filtros, antes de Spring Security):

- Pone un `requestId` en el MDC: toda línea del pedido lo lleva. El patrón de consola lo muestra entre corchetes (`logging.pattern.correlation`).
- Lo devuelve en el encabezado `X-Request-Id` (y lo expone por CORS), para que quien reporta un error lo cite.
- Reutiliza el `X-Request-Id` del cliente **solo si es seguro** (`[A-Za-z0-9._-]{8,64}`); si no, genera uno. El valor viene de afuera y terminaría en cada línea.
- Escribe al final `evento=http.pedido.resuelto metodo=… ruta=… estado=… ms=…` (`http.pedido.fallido`, con traza, si nadie manejó la excepción). No registra la query ni los encabezados, y omite `/actuator/`.

En el consumidor de Kafka no hay pedido HTTP: ahí el contexto lo ponen el `eventId` y el `proceso`, como campos del evento.

### 5. Lo que no se registra nunca

Tokens (el del usuario y el técnico de la cátedra), contraseñas y sus hashes, **el teléfono**, nombres y apellidos del paciente o del usuario, **el nombre de usuario (`login`)**, la dirección de la cátedra, el `groupId` y el cuerpo completo de un mensaje. Solo **ids** (el id numérico del usuario, el de la reserva, el `reservationProcessId`).

En un login fallido no se escribe el nombre que se intentó (puede ser un dato personal o una carga hostil): se escribe el id si la cuenta existe, o `-` si no.

### 6. Cómo se hace cumplir

No depende de acordarse; lo vigilan pruebas:

- **ArchUnit** (`ArquitecturaTest.logsConLogEvent`): ninguna clase fuera del paquete `logging` puede llamar a `info`, `warn` o `error` de SLF4J. `debug` queda libre.
- **Escaneo del código** (`NormaDeLogsTest`): todo código de evento tiene la forma `dominio.accion` y ningún argumento de un evento nombra un dato prohibido (`password`, `phone`, `telefono`, nombres, `token`, `groupId`, `login`). Exige además que el escaneo encuentre eventos, para no pasar en vacío.
- **`LogEventTest`** y **`RequestLogFilterTest`**: la forma de la línea, el escape de saltos de línea, el corte de valores, la traza solo en `ERROR`, el identificador seguro y que se limpia al terminar.
- **Pruebas de cada flujo** con `LogCapture`: la reserva feliz deja `iniciado → hold.creado → hold.confirmado → http.pedido.resuelto` en orden y con el mismo `requestId`; el login y el registro dejan su evento sin el nombre de usuario; las credenciales rechazadas de la cátedra no filtran el token.

Se comprobó con mutaciones que las pruebas detectan: dejar de escapar el salto de línea, aceptar cualquier `X-Request-Id`, escribir el `login` en un login fallido, quitar un evento de la reserva y un `log.info` directo.

## Catálogo de eventos de cronos

| Evento | Nivel | Cuándo |
|---|---|---|
| `http.pedido.resuelto` / `http.pedido.fallido` | INFO / ERROR | Al terminar cada pedido (estado y duración) / si una excepción llegó sin manejar |
| `seguridad.acceso.no_autenticado` / `seguridad.acceso.denegado` | WARN | Un `401` / un `403` |
| `usuario.registrado` / `usuario.registro.rechazado` | INFO | Un registro / uno rechazado (`login_en_uso`, `email_en_uso`) |
| `usuario.login.ok` / `usuario.login.fallido` | INFO / WARN | Un login / uno fallido (`usuario_inexistente`, `clave_incorrecta`, `cuenta_inactiva`) |
| `reserva.proceso.iniciado` | INFO | Se guardó el proceso local, antes de pedir el hold |
| `reserva.hold.creado` / `reserva.hold.confirmado` | INFO | La cátedra creó el hold / confirmó y queda esperando el teléfono |
| `reserva.pedido.repetido` | INFO / WARN | Se repitió un pedido: qué se hizo (`se_retoma_la_confirmacion`, `se_devuelve_el_existente`, o `409` si sigue en curso) |
| `reserva.proceso.fallido` / `reserva.proceso.vencido` / `reserva.proceso.vencido_local` | INFO o WARN | Se cerró un proceso: `etapa` y `motivo`; la cátedra lo dio por vencido; su vencimiento ya había pasado al volver a pedir |
| `reserva.confirmacion.reconciliando` / `.incierta` / `.ya_aplicada` | INFO / WARN / INFO | Segundo intento de confirmar / sigue sin saberse (queda en `HELD`) / ya estaba confirmada |
| `catedra.operacion.rechazada` | INFO | La cátedra rechazó una operación por una regla de negocio (`motivo`) |
| `catedra.credencial.rechazada` | WARN | `401` o `403`: el token técnico no sirve (`accion=rotar_token_en_env`) |
| `catedra.llamada.fallida` / `.sin_respuesta` / `catedra.respuesta.ilegible` | WARN | HTTP `5xx` u otro / sin conexión o timeout / respuesta que no se pudo interpretar |
| `catedra.no_disponible` / `catalogo.no_disponible` / `base_de_datos.no_disponible` | WARN | Se respondió `503` al cliente |
| `catedra.rechazo_inesperado` | ERROR | La cátedra rechazó por un motivo que no debería ocurrir (se responde `502`) |
| `atlas.llamada.fallida` / `.sin_respuesta` / `atlas.respuesta.ilegible` | WARN | Lo mismo para atlas (`accion=revisar_claves_jwt_de_atlas_y_cronos` si fue `401` o `403`) |

### Eventos al aplicar lo que informa la cátedra por Kafka (issue #15, paso 2)

Llevan `id_evento` (el `eventId` de la cátedra), `tipo` (el `eventType`) y `proceso` (el `reservationProcessId`).

| Evento | Nivel | Cuándo |
|---|---|---|
| `kafka.evento.aplicado` | INFO | El evento cambió el proceso: `estado_anterior` y `estado_nuevo` |
| `kafka.evento.duplicado` | INFO | El mismo `eventId` ya estaba procesado (`accion=sin_efectos`) |
| `kafka.evento.ignorado` | INFO / WARN | No corresponde al estado actual: INFO si el proceso ya terminó (llegó tarde), WARN si es una anomalía (`motivo`: `estado_final`, `estado_no_corresponde`, `hold_distinto`, `ya_confirmada`, `otra_reserva_confirmada`). Queda registrado como procesado |
| `kafka.evento.proceso_desconocido` | WARN | Cronos no tiene ese proceso. No se marca: se reintenta o se estaciona |
| `kafka.evento.estacionado` | WARN | Se guardó en `unmatched_event` (`accion=estacionado` o `ya_estaba_estacionado`) |
| `kafka.evento.reintento` | INFO | Otro escritor cambió el proceso a la vez; se reintenta (hasta 3 intentos) |
| `reserva.confirmacion.carrera` | INFO | El evento llegó entre la respuesta REST de la cátedra y el guardado del pedido: se relee el proceso y se reaplica o se devuelve el ya avanzado |

Los eventos del consumidor en sí (arranque, mensaje ilegible, desconectado) y del teléfono enviado se agregan con los pasos 3 a 5.

## Alcance y límites

- **Cronos:** aplicado. 353 pruebas, 0 fallas.
- **Atlas-catalogo:** **no aplicado todavía.** Tiene 14 clases con logger, 30 llamadas y 3 clases de prueba que miran logs. Se migra en un PR aparte (norma, `LogEvent`, `requestId` y eventos de sincronización), para no tocar un servicio casi cerrado antes de la entrega. Hasta entonces los logs de atlas siguen en prosa y esta norma rige solo para cronos.
- **Un token o un nombre en TRACE de librerías.** Con `TRACE` en `org.hibernate` o `org.postgresql`, o `DEBUG` en Spring, las librerías pueden escribir valores enlazados al SQL o partes del pedido. La norma controla **lo que escribe cronos**, no lo que escriben las librerías: es un límite conocido y esos niveles no se activan fuera del desarrollo.
- **Los valores de los eventos no se filtran por contenido.** `NormaDeLogsTest` mira los **nombres** que se pasan (`password`, `token`, …), no el contenido de una variable llamada de otra forma. Por eso hay además pruebas de flujo que buscan secretos y nombres reales en lo escrito.
- **Sin JSON.** Se eligió `clave=valor` por legibilidad en consola y en una defensa oral. Spring Boot 4 trae logging estructurado (JSON); si hiciera falta mandar los logs a un agregador, los pares se pueden pasar a campos sin cambiar los códigos de evento.
- **Sin duración en las llamadas a la cátedra.** El `ms` está en la línea de cierre de cada pedido. Medir cada llamada por separado queda para cuando se mida el consumidor de Kafka.

## Consecuencias

- Todo código nuevo escribe sus hitos y sus fallas con `LogEvent`; el resto de los `log.info/warn/error` falla en `ArquitecturaTest`.
- Un evento nuevo se agrega al catálogo de este ADR. Cambiar el **código** de un evento es un cambio visible para quien lo busca: se evita, o se anota.
- Se cerró una fuga: el `403` ya no escribe el nombre de usuario.

## Cuándo revisar

- Si se migra atlas: actualizar "Alcance" y el catálogo.
- Si se agrega un agregador de logs: evaluar el JSON de Spring Boot sobre estos mismos códigos.
- Si aparece un dato nuevo que no debería llegar a un log (por ejemplo, el teléfono con el issue #15): sumarlo a la lista de la sección 5 y al escaneo de `NormaDeLogsTest`.

## Referencias

OWASP Logging Cheat Sheet; RFC 5424 (severidades); logfmt; `LogEvent`, `RequestLogFilter`, `NormaDeLogsTest` y `ArquitecturaTest` en `cronos-turnos`.
