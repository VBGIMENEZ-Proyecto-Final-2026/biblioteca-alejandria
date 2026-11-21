# Evidencia · Prueba cruzada: un token emitido por cronos-turnos, validado por atlas-catalogo (issue #7, etapa 5; issue #33 de atlas)

**Fecha:** 2026-11-20 · **Operación:** los dos servicios corrieron a la vez con `bootRun`, cada uno contra su PostgreSQL local (`cronos-db` 5434 y `atlas-db` 5433), y un script simuló el recorrido de un cliente con `curl`. El script es `scripts/recorrido-cliente.sh` de `cronos-turnos` y se puede repetir. Ningún token, clave ni contraseña real figura acá: el token se describe y se muestra recortado.

## Cómo se corrió

| Servicio | Cómo | Notas |
|---|---|---|
| `cronos-turnos` | `CRONOS_JWT_PRIVATE_KEY_LOCATION=<clave privada de desarrollo> ./gradlew bootRun` (rama `feature/usuarios-jwt`, commit `be39029`, puerto 8081) | La clave se pasó por variable de entorno, sin tocar el `.env`. |
| `atlas-catalogo` | `bootRun` en el puerto 8080, con `ATLAS_SYNC_ON_STARTUP`, `ATLAS_SYNC_PERIODIC_CHECK` y `ATLAS_SYNC_KAFKA_ENABLED` en `false` | **No se habló con la cátedra en esta corrida**: atlas respondió con la copia local que ya tenía (versión local 391, 24 profesionales y 8 categorías, sincronizada antes). Se desactivó la sincronización para que la prueba no dependiera de la red de la cátedra. |
| Claves | Atlas usa la **clave pública** del mismo par con el que firma cronos | Se verificó que la pública de atlas es la derivada de la privada de cronos (par de desarrollo, el mismo de `~/.atlas-dev/`). |

## Qué se probó (26 comprobaciones, 26 bien, 0 mal)

| Paso | Qué hace el cliente | Resultado |
|---|---|---|
| 0 | Mira la salud de los dos servicios | `200` y `200` |
| 1 | Se registra en cronos con el login en mayúsculas | `201`; se guardó en minúsculas, `activated: true`, `authorities: ["ROLE_USER"]` |
| 1 | Repite el registro con el login en minúsculas | `400 USERNAME_ALREADY_EXISTS` |
| 1 | Manda datos inválidos | `400 VALIDATION_ERROR` |
| 2 | Inicia sesión con contraseña equivocada y con un login inexistente | `401 INVALID_CREDENTIALS` las dos, **con el mismo cuerpo** |
| 2 | Inicia sesión bien (el login no distingue mayúsculas) | `200` con `id_token` |
| 3 | `GET /api/account` con su token | `200`, es **su** cuenta |
| 3 | `GET /api/account?login=admin&id=1` con su token | `200`, **sigue siendo su** cuenta: el servidor ignora los identificadores del cliente |
| 3 | `GET /api/account` sin token | `401 NO_AUTENTICADO` |
| 3 | Una ruta que cronos no habilita, con token | `403 SIN_PERMISO` |
| 4 | **El mismo token en atlas**: `GET /api/categories` | `200`, 8 categorías |
| 4 | `GET /api/professionals?size=3` | `200`, 24 profesionales en total |
| 4 | `GET /api/sync/status` (solo `ROLE_ADMIN`) | `403 SIN_PERMISO` |
| 5 | Atlas sin token; con un esquema que no es Bearer | `401 NO_AUTENTICADO` las dos |
| 5 | Atlas y cronos con la firma alterada | `401 NO_AUTENTICADO` los dos |
| 5 | Atlas y cronos con un token firmado con **otra clave** | `401 NO_AUTENTICADO` los dos |
| 5 | Atlas y cronos con un token **vencido** (hace 2 horas) | `401 NO_AUTENTICADO` los dos |
| 5 | Atlas con un token válido pero **sin `ROLE_USER`** | `403 SIN_PERMISO` |
| 5 | Inicia sesión mandando un token roto en el encabezado | `200`: las rutas públicas ignoran el encabezado |
| 6 | Elige un profesional y pide su detalle a atlas | `200`, con sus horarios semanales |

## El token emitido

- Cabecera: `alg: RS256`, `typ: JWT`.
- Claims: solo `sub` (el login en minúsculas), `auth` (`ROLE_USER`), `iat` y `exp`; una hora entre `iat` y `exp`. 488 caracteres.
- **Atlas lo aceptó sin hablar con cronos**: valida la firma con la clave pública. Esto cierra la duda que dejaba la evidencia [isla-2-usuarios-jwt](isla-2-usuarios-jwt.md), que solo había verificado la firma con `openssl`.

## Lo que muestra el paso 6 (y lo que no)

El cliente toma un profesional de atlas y el script imprime sus horarios semanales partidos en turnos de la duración que indica cada horario, para la próxima fecha de ese día. **Eso lo calcula el script, no cronos.** Cronos todavía no calcula disponibilidad, no pide holds ni guarda reservas, y el cálculo real restaría las ocupaciones de la cátedra, que acá no entran. Se incluye para mostrar qué dato le llega a cronos desde atlas y para explicar el flujo.

## Límites de esta evidencia

- **Es una corrida local con claves de desarrollo**, no un entorno de entrega. Todo va por HTTP, sin cifrar.
- **Atlas no sincronizó con la cátedra** durante la corrida (ver arriba). Lo que se prueba es la validación del token y la búsqueda sobre la copia local.
- **El token vencido y el de rol insuficiente no los emitió cronos**: el script los firma con la misma clave de desarrollo (`forjar`), porque cronos solo emite tokens de 1 hora o más y no se puede esperar a que venzan. Prueban cómo reacciona cada servicio, no cómo los emite cronos. Que cronos emite `ROLE_USER` con vigencia de 1 hora está en el token real de los pasos 2 y 4.
- **No hay usuario administrador**: el registro solo crea `ROLE_USER`, así que `GET /api/sync/status` de atlas solo se probó hasta el `403`. Falta el administrador para la demostración.
- **No es una prueba automática de integración** que corra en cada build: el script se ejecuta a mano con los dos servicios levantados. Dentro de cada servicio sí hay pruebas automáticas (122 en cronos, con las de seguridad y CORS; las de atlas en `SeguridadApiTest`).
- **No se probó una carrera real** (dos registros iguales a la vez), ni el tiempo de respuesta del login con usuario existente e inexistente.
- El usuario de prueba (`cliente.<marca de tiempo>`) se borró de la base de cronos al terminar (`LIMPIAR=1`).

## Qué cierra y qué falta

- **Cierra:** la etapa 5 del issue #7 de cronos y la condición del issue #33 de atlas ("atlas valida un token real de cronos con los claims `sub` y `auth`"). Cerrar el #33 lo decide el alumno.
- **Falta:** la etapa 6 (documentación al día), el PR de `feature/usuarios-jwt` a `dev`, el usuario administrador y todo lo de turnos y reservas.
