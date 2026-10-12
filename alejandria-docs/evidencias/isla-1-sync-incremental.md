# Evidencia · Sincronización contra la cátedra real (Isla 1, issue #19)

**Fecha:** 2026-10-12 · **Operación:** lectura de la cátedra (snapshot REST y metadata de Redis) y escritura solo en una base PostgreSQL de prueba, en un contenedor descartable

Host, puerto, usuario, contraseña, token y `groupId` omitidos a propósito (ver ADR 0001).

## Resultado

Se ejecutó tres veces seguidas el caso de uso `SyncCatalog` con el disparo de arranque, contra la cátedra real (REST y Redis) y una base vacía.

| Corrida | Resultado | Estado de `sync_state` | Copia local | Tiempo |
|---|---|---|---|---|
| 1 · base vacía | Snapshot por `BASE_VACIA`, sin leer Redis | versión 1, `IDLE`, resultado `SNAPSHOT`, sin error | 8 categorías, 24 profesionales, 44 horarios | alrededor de 2,4 s |
| 2 · copia al día | Plan `Noop`: la versión local (1) coincide con la vigente que informa Redis | versión 1, `IDLE`, resultado `NOOP`, sin error | igual | alrededor de 11,5 s (ver observaciones) |
| 3 · copia al día | `Noop` | igual | igual | alrededor de 0,3 s |

## Cómo se ejecutó

1. Las variables `CATEDRA_REST_BASE_URL`, `CATEDRA_ID_TOKEN` y `CATEDRA_REDIS_*` salieron del `.env` local, que no se versiona.
2. Se corrió un test temporal de JUnit con el contexto completo de la aplicación (cliente REST, cliente Redis, planificador y casos de uso reales) y PostgreSQL en un contenedor de Testcontainers. Escribe en un archivo solo versiones, estados y conteos.
3. El test temporal se borró después y no forma parte del repositorio. Las pruebas automatizadas simulan la cátedra (o usan un Redis en un contenedor) y no la llaman.

## Observaciones

- **Lo que se comprobó contra la cátedra real:** que la primera carga y la verificación posterior funcionan de punta a punta y que `current` y `oldest` de Redis (ambos 1) se interpretan bien. No se aplicó ninguna versión incremental real, porque la cátedra todavía publica solo la versión 1: esa parte (cambios, bajas, escaladas y fallas) está cubierta por las pruebas automatizadas, no por la cátedra real. Repetir la prueba cuando la cátedra publique una versión 2.
- **La primera conexión al Redis de la cátedra es lenta, la red y no el código.** Una conexión TCP desde la misma máquina tardó unos 4,3 s la primera vez y unos 0,24 s las siguientes. Con el timeout de conexión por defecto de 3 s, la primera lectura depende de los reintentos (2) y por eso la corrida 2 tardó unos 11,5 s; la corrida 3 reutilizó la conexión y tardó 0,3 s. No se cambió el valor por una sola medición. *Revisar:* si el arranque con versión local resulta lento en la práctica, subir `CATEDRA_REDIS_CONNECT_TIMEOUT` a 5 s.
- El arranque con la copia al día cuesta una lectura de Redis y una escritura corta (`NOOP`); la verificación periódica repite exactamente eso cada intervalo.
