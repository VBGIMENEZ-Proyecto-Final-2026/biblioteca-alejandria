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

### Eventos de la cancelación (issue #12)

**Ninguno escribe el motivo que escribió el usuario** (texto libre, hasta 500 caracteres): se manda a la cátedra y se descarta.

| Evento | Nivel | Cuándo |
|---|---|---|
| `reserva.cancelacion.confirmada` | INFO | La cátedra canceló y la reserva quedó `CANCELLED`: `usuario`, `reserva`, `proceso`, `estado` y `ms` |
| `reserva.cancelacion.ya_cancelada` | INFO | Se pidió cancelar una ya cancelada: se devuelve tal cual, sin llamar a la cátedra |
| `reserva.cancelacion.denegada` | INFO | Cronos no la manda a la cátedra: `motivo` (`no_existe_o_no_es_suya`, `no_esta_confirmada`, `motivo_demasiado_largo`) |
| `reserva.cancelacion.rechazada` | INFO | La cátedra rechazó: `motivo` es el código de la cátedra; `accion=el_estado_local_no_cambia`. No se reintenta |
| `reserva.cancelacion.reconciliando` | INFO | No se supo qué pasó: se repite una vez (`intento=2`) |
| `reserva.cancelacion.incierta` | WARN | Sigue sin saberse tras la reconciliación: la reserva sigue confirmada y repetir el pedido es seguro |
| `reserva.cancelacion.carrera` | INFO | El consumidor cambió el proceso a la vez: se reaplica o se devuelve el ya avanzado |

El motivo tampoco llega al log por otro camino: `CancelRequest` y el cuerpo del cliente HTTP tienen un `toString` que no lo imprime (con `TRACE`, Spring escribe los objetos que lee y que serializa), y el largo se valida en el caso de uso y no con anotaciones de Spring (que pueden repetir el valor rechazado).

### Eventos del teléfono (issue #15, paso 5)

**Ninguno escribe el número, el `groupId` técnico, el nombre del topic ni los servidores.** Solo ids.

| Evento | Nivel | Cuándo |
|---|---|---|
| `reserva.telefono.enviado` | INFO | Kafka confirmó el envío: `usuario`, `reserva`, `proceso`, `id_envio` (el `eventId` del mensaje) y `ms` |
| `reserva.telefono.rechazado` | INFO | Cronos no lo manda: `motivo` (`no_existe_o_no_es_suya`, `la_catedra_todavia_no_lo_pidio`, `ya_no_lo_espera`, `vencida`, `ya_enviado_sin_respuesta`, `formato_invalido`). Nunca el valor recibido, ni su largo |
| `reserva.telefono.no_enviado` | WARN | Kafka no confirmó a tiempo: `motivo` es el nombre de la clase de la causa. No se marcó nada; el usuario puede reintentar |
| `reserva.telefono.enviado_sin_marca` | WARN | El mensaje salió pero no se pudo guardar cuándo (`accion=el_envio_salio_la_marca_no_se_guardo`): el pedido igual responde bien, para que el usuario no lo reenvíe |

Cómo se evita que el número llegue a un log: `PhoneNumber`, `PhoneSubmission`, `SubmitPhoneCommand` y `PhoneRequest` tienen un `toString` que no lo imprime (con `TRACE`, Spring escribe los objetos que lee del cuerpo); el error de validación no se hace con anotaciones de Spring (que pueden repetir el valor rechazado) sino en el caso de uso, con mensajes fijos; y `NormaDeLogsTest` prohíbe pasar como valor nada que se llame `phone` o `telefono`. El productor de Kafka escribe el valor de cada registro a nivel `TRACE`: las librerías están en `ERROR`.

### Eventos del consumidor de Kafka (issue #15, paso 4)

Mientras se procesa un mensaje, el lugar del `requestId` lo ocupa **`kafka-<partición>-<offset>`**: todas las líneas de ese mensaje lo llevan (incluidas las de `kafka.evento.*` de arriba). Los mensajes se identifican por partición y offset, **nunca por el nombre del topic** (contiene el `groupId` de la cuenta).

| Evento | Nivel | Cuándo |
|---|---|---|
| `kafka.mensaje.ilegible` | WARN | El mensaje no se entiende: `motivo` (`json_ilegible`, `falta_campo`, `campo_invalido`, `schema_no_soportado`, `mensaje_vacio`...) y `campo`. **Sin el contenido.** Se descarta y se confirma el offset |
| `kafka.mensaje.saltado` | INFO | Un tipo de evento que cronos no usa (`tipo`); se ignora y se confirma |
| `kafka.mensaje.reintento` | WARN | **Una línea por cada reintento**: `tipo_de_falla` (`proceso_desconocido`, `infraestructura_sin_respuesta`, `el_mensaje_falla`), `motivo` y `causa_raiz` (nombres de clase, nunca el mensaje), `intento` y `espera_ms` |
| `kafka.mensaje.agotado` | WARN / ERROR | Se acabaron los intentos: se estaciona y se confirma el offset. WARN si el proceso no existía (`UNKNOWN_PROCESS`); ERROR si el mensaje falla por sí mismo (`PROCESSING_FAILED`, con `excepcion` y `causa_raiz`, sin traza) |
| `kafka.consumidor.iniciado` / `.detenido` | INFO | El contenedor arrancó / se detuvo |
| `kafka.consumidor.no_inicia` | WARN | No se pudo construir el cliente (un host que no resuelve): `motivo` es el nombre de la clase, **sin el mensaje**, por prudencia; `reintento_en`. Cronos sigue atendiendo pedidos |
| `kafka.consumidor.sin_particiones` | WARN | El consumidor lleva un rato sin particiones asignadas (`segundos_sin_asignacion`): **es lo que se ve cuando Kafka no responde** y reemplaza a los avisos de la librería. Cada 30 s mientras dure |
| `kafka.consumidor.particiones_asignadas` / `.revocadas` | INFO | `cantidad`. Reemplaza al log de la librería, que escribe el grupo y el topic |

**Qué se hizo para que no se filtre el `groupId` ni la dirección de la cátedra** (y qué no alcanza):

- **Con Kafka caído, la librería los escribía en `WARN`, en cada reintento de conexión**: `[Consumer clientId=..., groupId=<grupo>] Connection to node -1 (<servidor>) could not be established`. Se midió el 2026-11-22 levantando cronos con Kafka inaccesible; la primera versión del consumidor solo había bajado las librerías a `WARN` y la prueba de fuga solo cubría el caso en que Kafka funciona. Ahora `org.apache.kafka` y `org.springframework.kafka` quedan en **`ERROR`**, y `ConsumerIdleLogger` escribe `kafka.consumidor.sin_particiones` para no quedar ciegos. `ConsumidorKafkaInaccesibleTest` mira todo lo escrito a nivel `WARN` o más con Kafka caído y exige que no aparezcan el grupo, el topic ni la dirección.
- Se fija un `client.id` propio (`cronos-eventos-de-reserva`): el que arma el cliente por defecto lleva el nombre del grupo (`consumer-<grupo>-<n>`, comprobado con el cliente real) y aparece en sus logs, sus métricas y los del broker.
- Se registra el nombre de la clase de una excepción, nunca su mensaje: el de una falla de base de datos puede traer la fila con los nombres del paciente. (Para un host que no resuelve el mensaje del cliente de Kafka es `No resolvable bootstrap urls given in bootstrap.servers`, **sin** la dirección; se omite igual, por prudencia.)
- `NormaDeLogsTest` prohíbe pasar como valor nada que se llame `topic`, `bootstrap` o `consumerGroup`.
- **Límite conocido:** un error de esas librerías a nivel `ERROR` (por ejemplo, una falla de autorización sobre el grupo) podría incluir el grupo o el servidor, y no se enmascara. Tampoco el nombre del topic en las métricas de JMX, que el JDK escribe solo a nivel `TRACE`.

## Alcance y límites

- **Cronos:** aplicado. 488 pruebas, 0 fallas (con los eventos de Kafka).
- **Atlas-catalogo:** **no aplicado todavía.** Tiene 14 clases con logger, 30 llamadas y 3 clases de prueba que miran logs. Se migra en un PR aparte (norma, `LogEvent`, `requestId` y eventos de sincronización), para no tocar un servicio casi cerrado antes de la entrega. Hasta entonces los logs de atlas siguen en prosa y esta norma rige solo para cronos. **Al migrarlo hay que corregir una fuga que se vio al escribir el consumidor de cronos.** Atlas no configura ningún nivel de log para las librerías de Kafka, así que con los valores por defecto el cliente escribe el grupo y los servidores en `INFO` al armarse y en `WARN` en cada reintento cuando Kafka no responde. Además atlas escribe `record.topic()` en dos de sus logs (el topic del catálogo contiene el `groupId` de la cuenta) y tiene el `client.id` por defecto, que lleva el grupo. Es lo mismo que se corrigió en cronos: niveles `ERROR` para las librerías, `client.id` propio, no escribir el topic y un aviso propio cuando no hay particiones.
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
