# Evidencia · Corrida real de punta a punta con la cátedra (issues #12, #13 y #15 de cronos-turnos)

**Fecha:** 2026-11-22 (noche) · **Operación:** atlas-catalogo y cronos-turnos (rama `dev`, con los PR #17 a #21 mergeados) corrieron con `bootRun`, con su PostgreSQL local y **la cátedra real** (REST y Kafka; dirección, token y `groupId` en el `.env`, nunca en este documento). Teléfono **inventado** (`+5492615551234`) y pacientes ficticios. Profesional 218, turnos del martes 2026-12-01.

## Qué se probó

| # | Prueba | Resultado |
|---|---|---|
| 1 | **Reserva feliz.** `POST /api/reservations` (15:00) | `202`, `WAITING_FOR_PHONE`, `expiresAt` a diez minutos. **Llegó por Kafka el `AdditionalInformationRequested` real** y la reserva guardó su `requestEventId` (1 s después) |
| 2 | `POST /api/reservations/{id}/phone` | `202`, `phoneSubmitted=true`. **20 s después llegó el `AppointmentConfirmed` real** y la reserva pasó a `CONFIRMED` con el id de la reserva de la cátedra. El número no aparece en el log de cronos |
| 3 | Consulta de la reserva propia | `200`, `CONFIRMED` |
| 4 | **Acceso cruzado:** otro usuario consulta y cancela esa reserva, y lista las suyas | `404 RESERVATION_NOT_FOUND` en ambas (el mismo que una inexistente) y listado vacío |
| 5 | **Cancelación real:** `POST .../cancel` | `200`, `CANCELLED` en 494 ms. **El `AppointmentCancelled` real que llegó después se ignoró** (`kafka.evento.ignorado`, `motivo=estado_final`, `accion=registrado_sin_cambios`) |
| 6 | **Vencimiento real:** segunda reserva (15:30) sin mandar el teléfono | A los ~10 minutos **llegó el `AppointmentProcessExpired` real** (12 s después de `expiresAt`, antes de que el barrido propio tuviera que actuar) y la reserva pasó a `EXPIRED` |
| 7 | **Duplicado real:** con cronos detenido se retrocedió el offset del grupo propio de 10 a 6 y se arrancó de nuevo | Se releyeron los 4 eventos reales (`Requested` ×2, `Confirmed`, `Cancelled`): los cuatro dieron `kafka.evento.duplicado accion=sin_efectos` y **la base quedó idéntica** (mismos estados, versiones y fechas de modificación) |
| 8 | **Reinicio con un proceso pendiente:** la reserva 6 estaba `WAITING_FOR_PHONE` al detener y arrancar cronos | Sobrevivió intacta; la pasada de recuperación del arranque no tenía nada que cerrar y el vencimiento posterior llegó por Kafka |
| 9 | **Mensajes viejos al arrancar con `earliest`:** el topic traía 6 mensajes de las pruebas del 2026-11-21 de procesos que ya no existen | Tras 3 intentos cada uno se **estacionó en `unmatched_event`** (`UNKNOWN_PROCESS`) y se confirmó el offset: no trabaron el consumo |

Al terminar no queda ningún hold ni reserva abierta en la cátedra (una cancelada y una vencida).

## Lo que sí y lo que no prueba

- **Sí prueba**, contra la cátedra real: el ciclo completo (hold, confirmación inicial, pedido de información por Kafka, envío del teléfono por Kafka, confirmación por Kafka), la cancelación por REST y su evento, el vencimiento por evento, la idempotencia con un reinicio y un retroceso real del offset, y el estacionado de eventos de procesos desconocidos.
- **No prueba**:
  - **La rama del teléfono rechazado** (`AdditionalInformationRejected`): cronos valida el número igual que la cátedra, así que no se pudo provocar un rechazo real. Está probada con la cátedra simulada (`TelefonoDePunteAPunteTest`).
  - **La recuperación actuando sobre datos reales:** en esta corrida no había procesos abandonados que recuperar (el barrido y la reconciliación de `HELD` están probados en `ReinicioConPendientesTest` con una segunda aplicación y una cátedra simulada).
  - **Un fallo real de la cátedra** (caída, lentitud): cubierto con servidores simulados.
- HTTP y Kafka sin cifrar (la cátedra no pide TLS ni autenticación); usuarios de prueba y claves de desarrollo.

## Cómo repetirlo

Con `dev` en `7cfec5e` o posterior, el `.env` de cronos completo y las dos bases arriba: levantar atlas (con `ATLAS_SYNC_ON_STARTUP=false`) y cronos (con `CRONOS_JWT_PRIVATE_KEY_LOCATION`), registrar un usuario y seguir la tabla. El retroceso del offset exige que cronos esté detenido (el grupo tiene que estar vacío). **Tiene efectos reales en un servicio compartido: avisar antes.**
