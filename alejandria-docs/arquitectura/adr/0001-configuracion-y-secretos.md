# ADR 0001 · Configuración y secretos

**Estado:** aceptado · **Contexto:** Isla 0, issue #4

## Contexto
Los backends necesitan valores sensibles (JWT técnico, credenciales de Redis, bootstrap de Kafka, URL de la cátedra). Los repos son públicos.

## Decisión
- Cada repo tiene un `.env` local, ignorado por git, y un `.env.example` versionado solo con placeholders.
- Spring lee todo por variables de entorno.
- `atlas-catalogo` y `cronos-turnos` comparten el mismo set `CATEDRA_*`, con nombres derivados del campo `integration` de `POST /api/student/register`:

| Variable | Origen |
|---|---|
| `CATEDRA_REST_BASE_URL` | Documentación de la cátedra (no viene en la respuesta) |
| `CATEDRA_ID_TOKEN` | `id_token` |
| `CATEDRA_GROUP_ID` | `groupId` |
| `CATEDRA_REDIS_HOST` / `_PORT` / `_USERNAME` / `_PASSWORD` | `redisHost` / `redisPort` / `redisUsername` / `redisPassword` |
| `CATEDRA_REDIS_READ_NAMESPACE` / `_WRITE_NAMESPACE` | `redisReadNamespace` / `redisWriteNamespace` |
| `CATEDRA_KAFKA_BOOTSTRAP_SERVERS` | `kafkaBootstrapServers` |
| `CATEDRA_KAFKA_CATALOG_TOPIC` | `kafkaCatalogTopic` |
| `CATEDRA_KAFKA_CONSUMER_GROUP_ID` | `kafkaConsumerGroupId` |
| `CATEDRA_KAFKA_APPOINTMENT_ACTIONS_TOPIC` / `_PHONE_TOPIC` | `kafkaAppointmentActionsTopic` / `kafkaAppointmentPhoneTopic` |

- Cada backend suma sus variables propias de base de datos (`ATLAS_DB_*`, `CRONOS_DB_*`), que se definen en el issue #6.
- `hermes-app` no usa `CATEDRA_*`: solo conoce las URL de sus backends.
- Los valores reales se guardan fuera de los repos (por ejemplo en `~/.config/<proyecto>/`) y se copian al `.env` de cada uno.

## Consecuencias
- Ningún repo contiene secretos, IPs ni el `groupId` real; en los ejemplos va como `<groupId>`.
- Rotar el token implica actualizar el `.env` de ambos backends.
