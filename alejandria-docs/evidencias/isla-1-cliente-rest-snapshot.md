# Evidencia · Cliente REST del snapshot contra la cátedra real (Isla 1, issue #12)

**Fecha:** 2026-10-11 · **Operación:** solo lectura (`GET /api/synchronization/snapshot`)

Host, puerto, token y `groupId` omitidos a propósito (ver ADR 0001).

## Resultado

| Dato | Valor |
|---|---|
| Resultado | El cliente pidió el snapshot, lo interpretó y lo convirtió al modelo propio sin errores |
| `snapshotVersion` | 1 (coincide con la versión vigente que informó el [smoke test](isla-0-smoke-test.md)) |
| Categorías | 8 |
| Profesionales | 24 |
| Horarios semanales | 44 |
| Tiempo total | alrededor de 2,7 s (un único pedido, sin reintentos) |

## Cómo se ejecutó

1. `CATEDRA_REST_BASE_URL` y `CATEDRA_ID_TOKEN` salieron del `.env` local, que no se versiona.
2. Se corrió un test temporal de JUnit que arma el cliente con la misma configuración de producción (`CatedraRestConfig`), llama a `fetchSnapshot()` e imprime solo la versión y los conteos, o la clase, el `status` y el `code` si hubiera fallado.
3. El test temporal se borró después y no forma parte del repositorio. Las pruebas automatizadas del cliente usan un servidor local y no llaman a la cátedra.

## Observaciones

- Los conteos coinciden con el orden de magnitud del smoke test de la Isla 0 (una respuesta de 14 491 bytes).
- No se inspeccionó el formato exacto de las horas del snapshot real: la lectura de `HH:mm` y `HH:mm:ss` está cubierta por las pruebas automatizadas, y el cliente real no devolvió errores de interpretación.
- Falta repetir la prueba cuando exista una versión mayor a 1, para comprobar que el cliente sigue leyendo bien un catálogo con cambios.
