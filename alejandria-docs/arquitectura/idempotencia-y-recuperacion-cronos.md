# Procesamiento idempotente y recuperación en cronos-turnos

**Actualizado:** 2026-11-22 · **Cubre:** la explicación obligatoria del enunciado (sección 12) sobre el procesamiento idempotente y la recuperación ante mensajes **duplicados, perdidos o fuera de orden**, más los timeouts, los vencimientos y el reinicio. La parte de atlas (copia del catálogo) está en [sincronización de atlas](sincronizacion-atlas-catalogo.md).

## En una frase

Cronos nunca asume que un mensaje llega una sola vez, ni a tiempo, ni en orden, ni que una llamada que expiró haya fallado. Cada efecto se aplica **una sola vez** (idempotencia por `eventId`, en la misma transacción que el cambio), un estado final **nunca retrocede**, el consumidor **solo confirma el mensaje después de aplicarlo**, y todo lo que quedó a medias lo cierra o lo reconcilia una tarea propia, sin depender de que llegue otro evento.

## Los tres problemas del enunciado

### 1. Mensajes duplicados

Kafka entrega "al menos una vez": un mensaje puede llegar de nuevo (reinicio del consumidor, offset retrocedido, reenvío de la cátedra).

| Mecanismo | Cómo funciona | Dónde |
|---|---|---|
| **Tabla `processed_event`** | La clave primaria es el `eventId` de la cátedra. Antes de aplicar un evento se inserta con `INSERT … ON CONFLICT DO NOTHING`: si no inserta, ya se había procesado y no se hace nada | `JdbcEventLog`, `ProcessReservationEvent` |
| **Misma transacción** | Marcar el `eventId` y cambiar el estado del proceso van juntos. Si el guardado falla, el evento **no** queda marcado y se reintenta entero; si quedó marcado, su efecto está guardado. Nunca se aplica dos veces ni a medias | `TransactionRunner` (el puerto; Spring lo implementa en el adaptador, así `application` no conoce a Spring) |
| **Dos copias a la vez** | La segunda espera a la primera en la base y recibe `DUPLICATE`. Con 8 hilos y el mismo evento: 1 `APPLIED` y 7 `DUPLICATE` | prueba `dosEventosIgualesALaVezSeAplicanUnaSolaVez` |
| **Un evento ignorado también se marca** | Un evento que no corresponde al estado (por ejemplo un `Cancelled` de algo que no estaba confirmado) no cambia nada, pero queda registrado, para que su duplicado tampoco haga nada | `unDuplicadoDeUnEventoIgnoradoTambienSeReconoce` |
| **Las operaciones REST también son idempotentes** | Pedir dos veces el mismo turno devuelve el **mismo** proceso (índice único parcial `reservation_process_active_slot`: un usuario no puede tener dos procesos activos para el mismo turno, ni con dos pedidos simultáneos). Repetir la confirmación de un hold que ya estaba confirmado (`RESERVATION_PROCESS_ALREADY_CONFIRMED`) cuenta como éxito. Cancelar una reserva ya cancelada la devuelve sin llamar a la cátedra | `StartReservation`, `CancelReservation` |
| **El teléfono no se duplica** | Un envío por cada pedido de la cátedra: el segundo recibe `409 PHONE_ALREADY_SUBMITTED`. Cada envío lleva un `eventId` nuevo; un rechazo o un pedido nuevo de la cátedra libera el siguiente | `SubmitPhone` |

**Evidencia real (2026-11-22):** con cronos detenido se retrocedió el offset del grupo propio de 10 a 6, se arrancó de nuevo y se releyeron cuatro eventos reales: los cuatro dieron `kafka.evento.duplicado accion=sin_efectos` y la base quedó idéntica (estados, versiones y fechas de modificación).

### 2. Mensajes perdidos

Un mensaje "perdido" tiene dos orígenes: cronos lo descarta por error, o cronos no estaba para recibirlo.

| Riesgo | Qué lo evita |
|---|---|
| Confirmar el offset y caerse antes de aplicar | **El offset se confirma recién después de la transacción** (un mensaje por vez). Si cronos se cae antes, el mensaje se vuelve a leer y la idempotencia lo absorbe. Probado: `elOffsetSeConfirmaSoloDespuesDeAplicarElCambio` (fila bloqueada con `FOR UPDATE`) |
| Una falla pasajera de la base | El mensaje se reintenta **sin límite**, con espera creciente (hasta 30 s). No se descarta ni se saltea: perder una confirmación dejaría una reserva inconsistente. Probado: `unaCaidaPasajeraDeLaBaseSeReintentaSinLimiteYElMensajeNoSePierdeNiSeSaltea` |
| Cronos apagado o sin Kafka cuando se publicó | El grupo es propio (`<grupo>-cronos`) y **lee desde el principio si no tiene offset** (`earliest`); si ya tiene, retoma donde quedó. Cronos **arranca igual aunque Kafka no responda** y reintenta conectarse cada 10 s |
| Kafka caído mucho tiempo: el evento de expiración nunca llega | El **barrido de vencimiento** cierra el proceso por su propio `expiresAt` sin necesitar ningún evento (ver Recuperación) |
| La respuesta REST se perdió (timeout) pero la cátedra sí procesó | **Reconciliación**: se repite la operación, que es idempotente en la cátedra. Un timeout no prueba que la operación falló (referencia 18.4) |

### 3. Mensajes fuera de orden

Con una sola partición por topic el orden **por proceso** está garantizado por Kafka (la clave del mensaje es el `reservationProcessId`). Lo que sí puede pasar es que el mensaje y la respuesta REST **se crucen**, o que un evento llegue cuando el proceso ya no lo admite.

| Situación | Qué hace cronos |
|---|---|
| `AdditionalInformationRequested` llega **antes** de que cronos termine de guardar la respuesta REST de la confirmación (pasó en la corrida real: 1 s después) | Guarda el `requestEventId` sin cambiar el estado. Cuando el guardado del pedido choca con el bloqueo optimista (`version`), se **relee y se reaplica** sobre la fila fresca; el usuario no ve un error aunque la cátedra ya confirmó. Probado: `siElEventoDeLaCatedraLlegaEntreLaConfirmacionYElGuardadoNoHayErrorYSeConservaElPedidoDeTelefono` |
| `AppointmentConfirmed` con el proceso todavía en `HELD` | Aplica dos transiciones seguidas en la misma transacción (`HELD → WAITING_FOR_PHONE → CONFIRMED`): el historial no salta estados |
| Un evento **tardío** después de un estado final (`Confirmed` tras `Expired`, `Cancelled` tras una cancelación por REST) | **No cambia nada**; queda registrado como `IGNORED` (`motivo=estado_final`). Un estado final no retrocede nunca. Evidencia real: el `AppointmentCancelled` posterior a la cancelación por REST |
| Evento de **otro hold** u otra reserva distinta de la confirmada | Se ignora y se registra como anomalía (WARN) |
| Evento de un **proceso que cronos no conoce** (base borrada, otra corrida) o que ganó una carrera contra el guardado | **No se marca.** Se reintenta 3 veces con espera creciente; si sigue sin existir, se **estaciona** en `unmatched_event` (sin datos personales) y se confirma el offset. No traba la partición. Evidencia real: los 6 mensajes viejos del topic |
| Mensaje ilegible (JSON roto, falta `eventId`, `schemaVersion` ≠ 1) o tipo que cronos no usa | Se registra **sin su contenido** y se descarta con el offset confirmado. El intérprete nunca lanza: se probó cortando cada mensaje real en cada posición y con 3000 alterados al azar |

La máquina de estados que lo hace posible está en [arquitectura general](arquitectura-general.md#máquina-de-estados-de-una-reserva): los finales (`EXPIRED`, `INVALID`, `FAILED`, `CANCELLED`) no tienen salida, y `CONFIRMED` solo pasa a `CANCELLED`.

## Política por tipo de falla del consumidor

Con una sola partición un mensaje no se puede saltear sin romper el orden de los eventos de un proceso, así que cada falla tiene su política (`ConsumerErrorPolicy`):

| Falla | Reintentos | Al agotarlos |
|---|---|---|
| El proceso del evento no existe | 3, con espera creciente | Se estaciona (`UNKNOWN_PROCESS`) y se confirma el offset |
| La base no responde ahora | **Sin límite**, espera creciente hasta 30 s | No se agotan: el mensaje no se pierde ni se saltea |
| El mensaje falla siempre por sí mismo | 3, con espera creciente | Se estaciona (`PROCESSING_FAILED`) y se confirma el offset |
| Otro escritor cambió el proceso a la vez (bloqueo optimista) | 3, dentro del caso de uso | Si no se resuelve, sube y nada queda marcado: se reintenta |

Si estacionar falla (la base cayó justo ahí), el contenedor lo trata como una falla más y vuelve a intentarlo: **nunca se confirma un offset sin dejar rastro**.

## Recuperación al reiniciar y vencimiento propio

Todo lo anterior depende de que lleguen mensajes. Lo que sigue **no depende de ninguno**: una tarea (`RecoveryScheduler`) hace una pasada al arrancar y otra cada 30 s (`RecoverReservations`).

| Paso | Qué cierra o recupera | ¿Necesita la cátedra? |
|---|---|---|
| 1. Barrido de vencimiento | `HELD` o `WAITING_FOR_PHONE` con `expiresAt` pasado hace más de 2 min → `EXPIRED` | No |
| 2. Procesos sin hold | `STARTING` sin modificarse hace más de 2 min (cronos se cortó antes de obtener el hold) → `FAILED` (`INTERRUPTED_BEFORE_HOLD`). Si la cátedra había creado el hold, vence solo | No |
| 3. Holds sin confirmar | `HELD` abandonado → se repite la confirmación con el `holdId` guardado (idempotente) → `WAITING_FOR_PHONE`, o `EXPIRED`/`FAILED` si la cátedra lo da por terminado | Sí |

Decisiones que lo hacen seguro:

- **Gracia de 2 minutos** antes de cerrar por vencido: la cátedra puede confirmar justo antes de vencer y su evento estar todavía en camino. `EXPIRED` es final y un evento tardío no lo reabre; cerrar enseguida dejaría una reserva que la cátedra sí confirmó como vencida.
- **Solo procesos abandonados** (2 min sin modificarse): uno recién guardado puede tener un pedido del usuario en curso. Si coinciden dos escritores, gana el bloqueo optimista y el que pierde relee. Probado: si el consumidor confirma la reserva justo cuando el barrido iba a cerrarla, **no se la pisa con vencida**.
- **Reintentos con límite y observables.** Cada proceso se intenta lo que la confirmación normal (el primero y una reconciliación). Si la cátedra no responde, **se corta la pasada** sin probar los demás (cada uno gastaría su timeout); el proceso sigue en `HELD` y la pasada siguiente lo reintenta, como mucho hasta su `expiresAt`, cuando el barrido lo cierra. **Ningún proceso queda colgado, aunque la cátedra no vuelva nunca** (probado). Cada intento deja una línea de log con evento, proceso e intento, sin datos sensibles.
- **Cátedra o atlas caídos:** lo que los necesita responde `503` sin iniciar nada ni dejar un proceso a medias; lo que depende solo de datos propios (cuenta, consulta de reservas) sigue funcionando. Un pedido que falló por la cátedra caída queda `FAILED` (no `STARTING`) y se puede volver a pedir.

## Timeouts: una llamada que expiró no prueba que falló

| Operación | Si no se sabe qué pasó |
|---|---|
| Crear un hold | El proceso se cierra como `FAILED` (`CATEDRA_UNAVAILABLE`). Si el hold existe, vence solo y el turno reaparece libre |
| Confirmar un hold | **Una reconciliación** (repetir la confirmación, idempotente). Si sigue sin saberse, queda `HELD` y repetir el pedido o la recuperación lo retoma |
| Cancelar una reserva | **Una reconciliación** (la cancelación de la cátedra es idempotente). Si sigue sin saberse: `503` y la reserva queda `CONFIRMED`; repetir el pedido es seguro y, si la cátedra sí canceló, el evento `AppointmentCancelled` la actualiza |
| Enviar el teléfono | Se manda primero y se marca después; si Kafka no confirma el envío, `503` y no se marca como enviado ni se reintenta solo |

Un **rechazo** de la cátedra (`409`, `403`, `404`) nunca se reintenta: es una respuesta concreta, no una duda.

## Cómo se ve en el log

Cada decisión es una línea `evento=<dominio.accion>` ([ADR 0006](adr/0006-norma-de-logs.md)): `kafka.evento.aplicado`, `.duplicado`, `.ignorado`, `.proceso_desconocido`, `.estacionado`, `.reintento`; `reserva.confirmacion.carrera`, `.reconciliando`, `.incierta`; `reserva.proceso.vencido_por_barrido`; `reserva.recuperacion.sin_hold`, `.reconciliado`, `.catedra_no_responde`, `.pasada`. Los mensajes de Kafka se identifican por `kafka-<partición>-<offset>`, nunca por el nombre del topic (contiene el `groupId` de la cuenta). Nunca se escribe el contenido de un mensaje, el teléfono ni los nombres del paciente.

## Dónde está probado

| Garantía | Prueba |
|---|---|
| El mismo evento dos veces no repite efectos | `elMismoEventoDosVecesNoRepiteNingunEfecto`; con Kafka real: `elMismoEventoDosVecesSeAplicaUnaSolaVezYElOffsetAvanzaIgual` |
| Dos copias simultáneas se aplican una vez | `dosEventosIgualesALaVezSeAplicanUnaSolaVez` |
| Si el guardado falla, el evento no queda marcado | `siElGuardadoFallaElEventoNoQuedaMarcadoYSePuedeReintentar` |
| Un estado final no retrocede | `unEventoTardioDespuesDeUnEstadoFinalNoCambiaNadaPeroQuedaRegistrado`, `unaConfirmadaNoVenceNiSeInvalidaPorUnEventoTardio` |
| El offset se confirma después de aplicar | `elOffsetSeConfirmaSoloDespuesDeAplicarElCambio` |
| Reinicio y offset retrocedido: los duplicados no cambian nada | `alReiniciarRetomaDesdeElOffsetConfirmadoYSiSeRetrocedeLosDuplicadosNoCambianNada` |
| Evento de un proceso desconocido: reintenta, estaciona y sigue | `unEventoDeUnProcesoQueNoExisteSeReintentaSeEstacionaYElConsumoSigue` |
| La base cae y vuelve: no se pierde el mensaje | `unaCaidaPasajeraDeLaBaseSeReintentaSinLimiteYElMensajeNoSePierdeNiSeSaltea` |
| El evento le gana a la respuesta REST | `siElEventoDeLaCatedraLlegaEntreLaConfirmacionYElGuardadoNoHayErrorYSeConservaElPedidoDeTelefono`, `siElEventoYaAdelantoElProcesoSeDevuelveTalCualEnLugarDePisarlo` y, con Kafka real, `unEventoQueGanoLaCarreraContraElGuardadoDelProcesoSeAplicaEnUnReintentoSinEstacionarse` |
| Reinicio con procesos pendientes | `ReinicioConPendientesTest` (una segunda aplicación completa sobre la misma base) |
| Ningún proceso queda sin salida, aun con la cátedra caída | `RecoverReservationsTest` (`ningunEstadoNoFinalQuedaSinSalida…`, `conLaCatedraCaidaParaSiempre…`) |
| Cátedra y atlas caídos a la vez | `ServiciosCaidosApiTest` |

Las 664 pruebas corren con `./gradlew test` (PostgreSQL y Kafka reales en contenedores). La corrida con la cátedra real está en la [evidencia](../evidencias/isla-2-corrida-real-kafka.md): reserva `CONFIRMED` por Kafka real, cancelación y su evento tardío, vencimiento real, duplicado real con el offset retrocedido, reinicio con un proceso pendiente y 6 mensajes viejos estacionados.

## Límites conocidos

- **No se concilia contra el listado de la cátedra** (`GET /api/appointments`): si Kafka estuviera caído más que la gracia después de un vencimiento, una confirmación real podría llegar a un proceso ya cerrado como vencido.
- **Un hold huérfano cuyo id nunca se guardó** no se puede recuperar: se desconoce. Vence solo.
- **Varias instancias de cronos a la vez:** las pasadas de recuperación se pisarían sin daño (el bloqueo optimista decide) y el consumidor comparte el grupo, pero no se probó.
- **La rama del teléfono rechazado** no se pudo provocar con la cátedra real (cronos valida el número igual que ella); está probada con la cátedra simulada.
- La **idempotencia de atlas** no usa una tabla de eventos: compara versiones (ver su documento de sincronización).
