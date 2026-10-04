# Evidencia · Smoke test de integración (Isla 0, issue #7)

**Fecha:** 2026-10-04 · **Cuenta técnica:** `PROVISIONED` · **Operaciones:** solo lectura

Hosts, puertos, credenciales y `groupId` omitidos a propósito (ver ADR 0001).

## Resultados

| Servicio | Prueba | Resultado |
|---|---|---|
| REST | `GET /api/synchronization/snapshot` con el JWT técnico | `HTTP 200`, 14 491 bytes |
| Redis | `GET catedra:sync:current-version` | `1` |
| Redis | `GET catedra:sync:oldest-available-version` | `1` |
| Redis | `HGETALL catedra:sync:metadata` | `currentVersion=1`, `oldestAvailableVersion=1`, `publishedAt=2026-09-22T00:08:12Z` |
| Kafka | Metadata del topic `catedra.catalog.<groupId>` | Existe: 1 broker, 1 partición, líder 1, réplicas e ISR 1 |
| Kafka | Lectura desde el inicio, sin consumer group | 0 mensajes |

## Cómo se ejecutó

- REST: `curl` con `Authorization: Bearer` y salida limitada al código HTTP y el tamaño.
- Redis: `valkey-cli` con el password por variable de entorno (`VALKEYCLI_AUTH`), nunca por argumento.
- Kafka: `kcat -L -t <topic>` y `kcat -C -o beginning -e` sin `-G`, para no crear consumer group ni mover offsets.

## Observaciones

- El topic de catálogo está vacío porque todavía no se publicó ningún `CatalogUpdated` (la versión vigente es la 1). Se espera el primer mensaje cuando la cátedra publique una versión nueva.
- La documentación de la cátedra no menciona autenticación para Kafka; la conexión funcionó sin credenciales dentro de la red ZeroTier. Conviene confirmarlo con el profe antes de la Isla 3.
- La latencia hacia el servidor ronda los 220-520 ms (ZeroTier), a tener en cuenta en timeouts.
