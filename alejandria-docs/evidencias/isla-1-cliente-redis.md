# Evidencia · Cliente Redis contra la cátedra real (Isla 1, issue #17)

**Fecha:** 2026-10-12 · **Operación:** solo lectura (`HGETALL` de la metadata, `GET` de `changes:{versión}` y `HMGET` de los Hashes de entidades)

Host, puerto, usuario, contraseña y `groupId` omitidos a propósito (ver ADR 0001).

## Resultado

| Dato | Valor |
|---|---|
| Resultado | El cliente leyó la metadata, los cambios de la versión vigente y las entidades afectadas, y las convirtió al modelo propio sin errores |
| `currentVersion` | 1 (coincide con el [snapshot REST](isla-1-cliente-rest-snapshot.md)) |
| `oldestAvailableVersion` | 1 |
| `publishedAt` | 2026-09-22T00:08:12Z |
| `changes:1` | 8 categorías, 24 profesionales y 44 horarios (IDs afectados) |
| Entidades leídas con esos IDs | 8 categorías, 24 profesionales y 44 horarios: no faltó ninguna |
| Tiempo total | alrededor de 4 s, incluida la primera conexión (un solo intento, sin reintentos) |

## Cómo se ejecutó

1. `CATEDRA_REDIS_HOST`, `CATEDRA_REDIS_PORT`, `CATEDRA_REDIS_USERNAME` y `CATEDRA_REDIS_PASSWORD` salieron del `.env` local, que no se versiona.
2. Se corrió un test temporal de JUnit que arma el cliente con la misma configuración de producción (`CatedraRedisConfig`), lee la metadata y, para cada versión de `oldest` a `current`, los cambios y las entidades afectadas, y escribe en un archivo solo versiones y conteos (o la clase de la excepción si fallara).
3. El test temporal se borró después y no forma parte del repositorio. Las pruebas automatizadas usan un Redis en un contenedor y no llaman a la cátedra.

## Observaciones

- Los conteos de `changes:1` coinciden con los del snapshot REST: con la versión 1, el "cambio" inicial es el catálogo completo.
- **Para la consulta 10 (`oldest-available-version`):** en la cátedra real `oldest = 1` y la clave `changes:1` **existe**. Es decir, `oldest` es al menos la primera versión que tiene `changes` disponible. Con un solo dato no se puede saber si, con versión local `oldest - 1`, alcanzaría aplicar desde `changes:oldest`; esa duda sigue abierta y el planificador mantiene la lectura literal (snapshot) hasta que responda el docente.
- No se probó contra una versión mayor a 1 ni con IDs ausentes del Hash: esos casos están cubiertos por las pruebas automatizadas, no por la cátedra real.
