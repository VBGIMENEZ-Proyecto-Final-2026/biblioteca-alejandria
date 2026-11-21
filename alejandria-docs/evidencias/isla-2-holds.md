# Evidencia · Holds contra la cátedra real (issue #11 de cronos-turnos)

**Fecha:** 2026-11-21 · **Operación:** cronos-turnos y atlas-catalogo corrieron con `bootRun` (cronos con su PostgreSQL local y la rama `feature/holds`) y **la cátedra real** (la URL y el token técnico de la cuenta del proyecto, leídos del `.env`, sin pasarlos por línea de comandos). Se registraron dos usuarios de prueba en cronos y se probó con `curl`. **Esta prueba tiene efectos reales**: creó tres holds en la cátedra, que vencen solos a los diez minutos. Ningún token, clave, dirección ni login real figura acá. Los usuarios y las reservas de prueba se borraron de la base local al terminar.

## Qué se probó

Profesional 218 (atiende los martes de 13:00 a 16:00, turnos de 30 minutos), turno del martes 2026-12-01 a las 15:30.

| # | Prueba | Resultado |
|---|---|---|
| 1 | Usuario A: `POST /api/reservations` | `202` en 0,9 s. Proceso `WAITING_FOR_PHONE` con `expiresAt` a diez minutos. La cátedra lo mostró en `appointment-occupancies` como `HELD` del 15:30 |
| 2 | Usuario A repite el mismo pedido | `202` en 11 ms, **el mismo proceso**; la cátedra siguió mostrando **un solo** hold |
| 3 | Usuario B pide el mismo turno | `409 SLOT_ALREADY_HELD` (la cátedra lo rechazó); su proceso quedó `FAILED` con ese motivo |
| 4 | Disponibilidad de cronos para ese día | 5 turnos: **el 15:30 desapareció** |
| 5 | Sin token / nombre del paciente de 1 letra / turno fuera de la agenda (14:45) | `401` / `400 VALIDATION_ERROR` / `400 INVALID_SLOT` (sin llamar a la cátedra) |
| 6 | El hold de A **venció solo** en la cátedra | A las 17:02:25 UTC; observado 11 s después. La disponibilidad de cronos volvió a mostrar 6 turnos |
| 7 | Usuario B vuelve a pedir el turno (su intento anterior quedó `FAILED` y el turno ya estaba libre) | `202`, **hold nuevo** (el tercero de la cátedra) |
| 8 | Usuario A pide de nuevo el turno después de que el de B venció, con el código corregido | `202`: su proceso viejo pasó a **`EXPIRED`** y se creó **uno nuevo** con un hold nuevo |
| 9 | Usuario A repite el pedido | Respuesta **idéntica byte a byte** a la primera |

Estado final de la base de cronos antes de borrarla: A (proceso 1) `EXPIRED`, B (proceso 2) `FAILED` por `SLOT_ALREADY_HELD`, B (proceso 3) `WAITING_FOR_PHONE`, A (proceso 4) `WAITING_FOR_PHONE`.

## Lo que encontró la prueba real

Los dobles de las pruebas automáticas no lo habían mostrado:

1. **La cátedra informa `expiresAt` con nanosegundos** (`2026-11-21T17:02:25.905856025Z`) y PostgreSQL guarda microsegundos. La primera respuesta de un pedido traía nanosegundos y un pedido repetido, leído de la base, microsegundos (paso 2). **Corregido** truncando los instantes a microsegundos en el dominio; la prueba 9 lo verifica con la cátedra real (cronos guarda `...847287Z`, la cátedra informa `...847287082Z`) y hay una prueba automática con nanosegundos que falla sin la corrección.
2. **El hold vence solo y cronos no se entera**: sin consumidor de Kafka todavía, el proceso de A quedó `WAITING_FOR_PHONE` aunque la cátedra ya lo había dado por vencido, y pedir de nuevo el turno devolvía ese proceso muerto. **Corregido** con una regla local: si el proceso activo ya pasó su `expiresAt`, se cierra como `EXPIRED` y se empieza uno nuevo (pasos 7 y 8).

## Lo que sí y lo que no prueba

- **Sí prueba**, contra la cátedra real: que crear y confirmar un hold funciona con el formato real; que la cuenta técnica se acepta; que el turno retenido desaparece de la disponibilidad y vuelve cuando vence; que la cátedra rechaza un turno tomado con `SLOT_ALREADY_HELD`; que el mismo pedido no crea dos holds; y que un usuario no ve ni retoma el proceso de otro.
- **No prueba**: Kafka. La cátedra publicó `AdditionalInformationRequested` al confirmarse cada hold, pero cronos todavía no lo consume (issue #15): ningún proceso pasó de `WAITING_FOR_PHONE`, no hay reserva `CONFIRMED` ni se probó la información adicional, el resultado final ni la idempotencia.
- **El proceso 3 de B quedó `WAITING_FOR_PHONE` aunque su hold venció**: nadie le volvió a pedir ese turno. Es el límite que cierran el evento de expiración (#15) y el barrido al reiniciar (#13).
- No se probó un fallo real de la cátedra (caída, lentitud) en esta corrida; esos casos están cubiertos con servidores simulados.
- Usuarios de prueba y claves de desarrollo; HTTP sin cifrar.

## Pruebas automáticas

325 pruebas, 0 fallas (111 nuevas). Diez mutaciones deliberadas fueron detectadas. Detalle en [implementación](../implementacion/cronos-turnos.md).
