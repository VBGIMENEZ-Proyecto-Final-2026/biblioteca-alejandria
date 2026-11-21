# Evidencia · Registro y login de cronos-turnos con la aplicación real (issue #7)

**Fecha:** 2026-11-19 · **Operación:** cronos-turnos corrió con `bootRun` contra su PostgreSQL del compose (local, puerto 5434) y la clave **de desarrollo** (`CRONOS_JWT_PRIVATE_KEY_LOCATION`), y se la probó con `curl`. No se llamó a la cátedra ni a atlas. El usuario de prueba (`smoke.test`) se borró de la base al terminar.

Ningún token, clave ni contraseña real figura acá. El token no se reproduce: se describe.

## Qué se probó

| Prueba | Resultado |
|---|---|
| `GET /actuator/health` | `200`, `UP` |
| `POST /api/register` con `login` en mayúsculas y email en mayúsculas | `201`; el usuario vuelve con `login` y `email` en minúsculas, `activated: true` y `authorities: ["ROLE_USER"]`; la respuesta no trae contraseña ni hash |
| `POST /api/register` repitiendo el login (en minúsculas) | `400`, `code: USERNAME_ALREADY_EXISTS`, como `problem+json` |
| `POST /api/authenticate` con contraseña equivocada | `401` |
| `POST /api/authenticate` con el login en otra capitalización y la contraseña correcta | `200` con `id_token` (478 caracteres) |

## El token emitido

- Encabezado: `alg: RS256`, `typ: JWT`.
- Claims: solo `sub` (el login en minúsculas), `auth` (`ROLE_USER`), `iat` y `exp`; una hora entre `iat` y `exp`.
- **Firma verificada con la clave pública de desarrollo** que atlas ya usa, con `openssl dgst -sha256 -verify`: `Verified OK`.

Esto prueba que el token es verificable con la clave pública, pero **no** que atlas lo acepte. Esa prueba (etapa 5) se hizo el 2026-11-20 y está en [isla-2-prueba-cruzada](isla-2-prueba-cruzada.md): atlas aceptó un token real de cronos.

## Arranque sin clave

La prueba automática `UsersConfigTest` cubre que sin `CRONOS_JWT_PRIVATE_KEY_LOCATION` ni `CRONOS_JWT_PRIVATE_KEY` la aplicación no arranca y dice qué falta, y que con un texto que no es un PEM falla sin repetir ese texto. No se repitió a mano con la aplicación real.

## Pruebas automáticas

86 pruebas, 0 fallas, 0 errores al 2026-11-19 (`./gradlew test`, con Podman). Dos mutaciones deliberadas fueron detectadas: quitar el hash de relleno que iguala los tiempos del login, y agregar el email como claim del token.

**Actualización 2026-11-21 (etapas 4 y 6):** 122 pruebas, 0 fallas, 0 errores (36 nuevas: `GET /api/account`, tokens malos, `401` y `403`, rutas públicas con encabezado roto, CORS y configuración). Otras dos mutaciones fueron detectadas: no exigir `sub` y `exp` en el token, y abrir `/api/account` a cualquier usuario autenticado. Lo que esas pruebas muestran con la aplicación corriendo (cuenta propia, tokens malos, `403`) está en la evidencia de la prueba cruzada.

## Límites de esta evidencia

- Es una corrida local con una clave de desarrollo, no un entorno de entrega.
- No se probó concurrencia (dos registros iguales a la vez); la restricción UNIQUE de la base y su traducción a `USERNAME_ALREADY_EXISTS` están cubiertas por una prueba del repositorio, no por una carrera real.
- No se midió el tiempo de respuesta del login con login existente e inexistente; la prueba solo verifica que se calcula el hash de relleno.
