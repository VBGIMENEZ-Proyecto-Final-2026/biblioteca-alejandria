# Evidencia · Disponibilidad de turnos de cronos-turnos con atlas real (issue #9)

**Fecha:** 2026-11-21 · **Operación:** cronos-turnos corrió con `bootRun` (puerto 8081, su PostgreSQL local) junto con **atlas-catalogo real** (puerto 8080, su copia local del catálogo, sincronización apagada), y se la probó con `curl`. **La cátedra no estuvo en esta primera corrida**: su red privada no era accesible en ese momento (el servidor no respondía a un ping ni a una conexión HTTP). En su lugar cronos habló con una **cátedra simulada** (un servidor local mínimo que devuelve ocupaciones fijas). Claves de desarrollo, por HTTP. Ningún token, clave ni dirección real figura acá. El usuario de prueba se borró de la base al terminar.

## Qué se probó

El profesional 207 de atlas atiende los lunes de 18:00 a 21:00 y los miércoles de 12:00 a 15:00, turnos de 30 minutos. Se pidió el rango del lunes 2026-11-23 al miércoles 2026-11-25, con la cátedra simulada informando tres ocupaciones: 18:30 `CONFIRMED`, 19:00 `HELD` y 12:30 `CONFIRMED`.

| Prueba | Resultado |
|---|---|
| `GET /api/professionals/207/availability?from=2026-11-23&to=2026-11-25` con el token de un usuario registrado y logueado en cronos | `200`. **9 turnos** (12 de la grilla menos 3 ocupados): lunes 18:00, 19:30, 20:00, 20:30; miércoles 12:00, 13:00, 13:30, 14:00, 14:30 |
| Qué recibió la cátedra simulada | **Una sola** consulta para todo el rango: `professionalId=207`, `from=2026-11-23`, `to=2026-11-25`, con un `Authorization: Bearer` que era el token técnico (el falso de la prueba), no el del usuario |
| Qué hizo atlas | Aceptó el JWT del usuario emitido por cronos y respondió el detalle del profesional con sus horarios |
| Sin token | `401 NO_AUTENTICADO` |
| Profesional que atlas no conoce (99999) | `404 PROFESSIONAL_NOT_FOUND` |
| Rango invertido | `400 INVALID_DATE_RANGE` |
| Fecha mal formada (`from=hoy`) | `400 VALIDATION_ERROR`, nombra el parámetro `from` y no repite el valor |
| Cátedra simulada apagada | `503 CATEDRA_UNAVAILABLE` en 0,32 s (un intento y un reintento) |
| Atlas apagado | `503 CATALOG_UNAVAILABLE` en 0,31 s |
| Log de cronos | Ninguna aparición del token del usuario ni del token técnico (0 coincidencias en el log de la corrida); sí las líneas "El catálogo no está disponible" y "La cátedra no está disponible" |

## Segunda corrida: con la cátedra real (2026-11-21, tarde)

La red privada de la cátedra (por ZeroTier) volvió a responder: REST con `200` en unos 0,5 s, y Kafka y Redis con el puerto abierto. Latencia de red de unos 280 ms. Cronos corrió con su propio `.env` (la URL y el token técnico reales de la cuenta del proyecto, sin pasarlos por línea de comandos) junto a atlas real. **Solo se hicieron lecturas** en la cátedra: no se creó ningún hold ni reserva. El token técnico es válido hasta octubre de 2027 y no aparece en el log de cronos (0 coincidencias).

| Prueba | Resultado |
|---|---|
| Consulta directa a la cátedra: `GET /api/appointment-occupancies` del profesional 207, del 23 al 29 de noviembre | `200` en 2,5 s, con la forma de la referencia (`professionalId`, `from`, `to`, `occupancies: []`) |
| La misma consulta con el rango invertido | `400` con `code: INVALID_DATE_RANGE`, como dice la referencia (13.1) |
| `GET /api/professionals/207/availability?from=2026-11-23&to=2026-11-25` con cronos, atlas y la cátedra reales | `200` en 0,86 s; **12 turnos** (la grilla completa: la cátedra no tiene ocupaciones de ese profesional esa semana) |
| Búsqueda de una ocupación real: se consultó a los profesionales habilitados hasta fin de año | Solo el profesional 218 tiene una: **2026-11-24, 14:30, `CONFIRMED`** |
| Disponibilidad de cronos del profesional 218 el 2026-11-24 (atiende los martes de 13:00 a 16:00, turnos de 30 minutos: 6 turnos) | `200`, **5 turnos** (13:00, 13:30, 14:00, 15:00, 15:30): **el de las 14:30 no aparece** |

Con esto queda verificado contra la cátedra real que el formato de las ocupaciones coincide con la referencia (cronos lo lee sin cambios), que la cuenta técnica funciona, que un turno `CONFIRMED` real se resta y que una lista vacía es una respuesta válida.

**Lo que sigue sin probarse contra la cátedra real:** un turno `HELD` (no había ninguno), el momento del día (los turnos que ya empezaron), las caídas (se probaron con una cátedra simulada apagada) y todo lo que tiene efectos: crear y confirmar un hold, que se hace con los holds.

## Lo que sí y lo que no prueba

- **Sí prueba** que cronos lee el JSON **real** de atlas (el contrato de `GET /api/professionals/{id}`), que atlas acepta el JWT que cronos reenvía, que la resta de ocupaciones y la grilla dan lo esperado con datos reales y que las dos caídas se traducen sin colgarse.
- **La primera corrida (la de arriba) no prueba nada contra la cátedra real**: usó una cátedra simulada porque su red no respondía. La segunda corrida (siguiente sección) sí, y cierra esa duda para las ocupaciones. Si la cátedra devolviera otra forma, cronos fallaría con `503 CATEDRA_UNAVAILABLE` en lugar de inventar turnos.
- La cátedra simulada aplica las mismas ocupaciones a cada día del rango; por eso los turnos de las 12:30 del miércoles y las 18:30 y 19:00 del lunes se restan y el resto no.
- No se probó el momento del día (los turnos que ya empezaron): las pruebas automáticas lo cubren con un reloj fijo, no esta corrida.
- Ningún dato quedó guardado en cronos (la base solo tiene usuarios).

## Pruebas automáticas

214 pruebas, 0 fallas (92 nuevas). Seis mutaciones deliberadas fueron detectadas: no restar los turnos bloqueados, ofrecer turnos que ya empezaron, aceptar turnos que no entran completos, seguir redirecciones, consultar a la cátedra aunque no haya grilla y dejar la ruta sin autenticación. Detalle en [implementación](../implementacion/cronos-turnos.md).
