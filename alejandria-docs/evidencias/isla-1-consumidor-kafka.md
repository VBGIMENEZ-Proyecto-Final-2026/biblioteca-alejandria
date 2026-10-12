# Evidencia · Consumidor de Kafka contra la cátedra real (Isla 1, issue #21)

**Fecha:** 2026-10-12 · **Operación:** el consumidor se une al consumer group de la integración y lee del topic del catálogo; no publica nada y no llegó ningún evento

Host, puerto, topic, consumer group y `groupId` omitidos a propósito (ver ADR 0001).

## Resultado

| Dato | Valor |
|---|---|
| Resultado | El consumidor arrancó con la configuración de producción, se unió al grupo y recibió la asignación de la partición |
| Particiones asignadas | 1 (coincide con el [smoke test](isla-0-smoke-test.md): el topic tiene una partición) |
| Tiempo hasta la asignación | alrededor de 2,3 s, medido desde que se creó el contexto de la aplicación |
| Estado de `sync_state` | sin cambios (versión local nula, `IDLE`, sin resultado): no llegó ningún evento |

## Cómo se ejecutó

1. `CATEDRA_KAFKA_BOOTSTRAP_SERVERS`, `CATEDRA_KAFKA_CATALOG_TOPIC` y `CATEDRA_KAFKA_CONSUMER_GROUP_ID` salieron del `.env` local, que no se versiona.
2. Se corrió un test temporal de JUnit con el contexto completo de la aplicación (consumidor de producción, `SyncCatalog` real y PostgreSQL en un contenedor descartable), que espera la asignación de la partición y escribe en un archivo solo conteos y tiempos.
3. El test temporal se borró después y no forma parte del repositorio. Las pruebas automatizadas usan un Kafka en un contenedor y no llaman a la cátedra.

## Observaciones

- **Lo que se comprobó contra la cátedra real:** que la conexión sin credenciales funciona (consistente con el smoke test de la Isla 0, que no mostró autenticación), que el nombre del grupo es válido y que la partición se asigna. Seguir sin autenticación es un supuesto: la referencia no la documenta y conviene confirmarlo con el docente antes de la Isla 3.
- **Lo que no se pudo comprobar:** un disparo real. El topic solo lo escribe la cátedra y no publicó ningún `CatalogUpdated` durante la prueba, así que el procesamiento de un evento (aplicar una versión, descartar un duplicado, confirmar el *offset*) está cubierto por las pruebas automatizadas con un Kafka real en un contenedor, no por la cátedra real. Repetir cuando la cátedra publique una versión.
- La prueba no confirmó ningún *offset* en el grupo real: sin eventos no hay nada que confirmar.
