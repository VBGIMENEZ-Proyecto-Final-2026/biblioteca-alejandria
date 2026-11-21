# Evidencia · Disponibilidad de turnos de cronos-turnos con atlas real (issue #9)

**Fecha:** 2026-11-21 · **Operación:** cronos-turnos corrió con `bootRun` (puerto 8081, su PostgreSQL local) junto con **atlas-catalogo real** (puerto 8080, su copia local del catálogo, sincronización apagada), y se la probó con `curl`. **La cátedra no estuvo en la prueba**: su red privada no era accesible (el servidor no respondía a un ping ni a una conexión HTTP). En su lugar cronos habló con una **cátedra simulada** (un servidor local mínimo que devuelve ocupaciones fijas). Claves de desarrollo, por HTTP. Ningún token, clave ni dirección real figura acá. El usuario de prueba se borró de la base al terminar.

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

## Lo que sí y lo que no prueba

- **Sí prueba** que cronos lee el JSON **real** de atlas (el contrato de `GET /api/professionals/{id}`), que atlas acepta el JWT que cronos reenvía, que la resta de ocupaciones y la grilla dan lo esperado con datos reales y que las dos caídas se traducen sin colgarse.
- **No prueba nada contra la cátedra real.** El formato de `GET /api/appointment-occupancies` se tomó de la referencia de integración (sección 8), no de una respuesta real. Si la cátedra devolviera otra forma, cronos fallaría con `503 CATEDRA_UNAVAILABLE` en lugar de inventar turnos (un campo desconocido se ignora; uno obligatorio ausente, o un estado desconocido, hace fallar la consulta). **Esta prueba está pendiente** hasta que la red de la cátedra esté accesible.
- La cátedra simulada aplica las mismas ocupaciones a cada día del rango; por eso los turnos de las 12:30 del miércoles y las 18:30 y 19:00 del lunes se restan y el resto no.
- No se probó el momento del día (los turnos que ya empezaron): las pruebas automáticas lo cubren con un reloj fijo, no esta corrida.
- Ningún dato quedó guardado en cronos (la base solo tiene usuarios).

## Pruebas automáticas

214 pruebas, 0 fallas (92 nuevas). Seis mutaciones deliberadas fueron detectadas: no restar los turnos bloqueados, ofrecer turnos que ya empezaron, aceptar turnos que no entran completos, seguir redirecciones, consultar a la cátedra aunque no haya grilla y dejar la ruta sin autenticación. Detalle en [implementación](../implementacion/cronos-turnos.md).
