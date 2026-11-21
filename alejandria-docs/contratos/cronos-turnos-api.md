# Contrato de cronos-turnos: usuarios y autenticación

**Versión 1 (parcial) · 2026-11-21.** Lo que `cronos-turnos` ofrece hoy a `hermes-app`: registro, inicio de sesión, emisión del JWT y consulta de la propia cuenta. Disponibilidad, bloqueos y reservas todavía no existen y se agregan a este contrato cuando se implementen. Lo que no está acá no es parte del contrato.

## 1. Alcance y reglas

- **Quién emite los tokens:** cronos-turnos (decisión del 2026-11-01, [ADR 0004](../arquitectura/adr/0004-autenticacion-entre-servicios.md)). Atlas solo los valida con la clave pública.
- **Sin JHipster:** el servicio implementa los usuarios con Spring Security y un contrato compatible con el usuario de JHipster, como pide el enunciado 3.2 ([ADR 0005](../arquitectura/adr/0005-usuarios-y-jwt-en-cronos-sin-jhipster.md)).
- **Base:** `http(s)://<host-de-cronos>:8081`. Formato `application/json`, UTF-8. Los errores son `application/problem+json`.
- **Rutas públicas:** `POST /api/register`, `POST /api/authenticate` y `GET /actuator/health`. Ignoran el encabezado `Authorization`: un token vencido guardado no impide volver a iniciar sesión. `GET /api/account` pide token. Todo lo demás se deniega.
- **No es la cuenta técnica de la cátedra.** Un usuario final y la cuenta técnica de integración son identidades distintas (enunciado 3.2): el JWT de la cátedra nunca se expone a la app.

## 2. Registro: `POST /api/register`

Sin autenticación. Cuerpo:

| Campo | Obligatorio | Regla |
|---|---|---|
| `login` | sí | 3 a 50; letras, números y `. _ @ -`. Se guarda en minúsculas y es único aunque cambien las mayúsculas. |
| `password` | sí | 4 a 100 caracteres. Se guarda con hash, nunca en claro. |
| `firstName`, `lastName` | no | Hasta 50. |
| `email` | no | Válido, 5 a 254. Se guarda en minúsculas. Único si se informa. |
| `imageUrl` | no | Hasta 256. |
| `langKey` | no | 2 a 10. Por defecto `es`. |

Cualquier otro campo (`id`, `activated`, `authorities`, fechas) **se ignora**: los decide el backend.

Respuesta `201 Created`, sin contraseña ni hash:

```json
{
  "id": 1,
  "login": "juan.perez",
  "firstName": "Juan",
  "lastName": null,
  "email": "juan@ejemplo.test",
  "imageUrl": null,
  "langKey": "es",
  "activated": true,
  "authorities": ["ROLE_USER"]
}
```

El usuario queda **activo** de inmediato y puede iniciar sesión sin verificar el correo (enunciado 3.2).

## 3. Inicio de sesión: `POST /api/authenticate`

Sin autenticación. Misma forma que el login de la cátedra (referencia de integración, 5.2):

```json
{ "username": "juan.perez", "password": "una-clave", "rememberMe": false }
```

| Campo | Regla |
|---|---|
| `username` | 1 a 254. No distingue mayúsculas. |
| `password` | 4 a 100. |
| `rememberMe` | Opcional. `true` pide la vigencia larga. |

Respuesta `200 OK`: `{ "id_token": "<jwt>" }`. El mismo token va en el encabezado `Authorization: Bearer <jwt>`.

### 3.1 El token

JWT firmado con **RS256**. Claims:

| Claim | Valor |
|---|---|
| `sub` | El `login` del usuario, en minúsculas. |
| `auth` | Las autoridades separadas por espacio, ordenadas (por ejemplo `ROLE_USER`). Es el claim que atlas lee, el mismo que usa JHipster. |
| `iat` | Momento de emisión. |
| `exp` | Vencimiento: 1 hora, o 30 días con `rememberMe` (configurable por `CRONOS_JWT_TTL` y `CRONOS_JWT_REMEMBER_ME_TTL`). |

No lleva email, nombres ni nada de la contraseña. No hay `iss`, `aud` ni `kid`. No hay refresco ni revocación: un token vale hasta que vence.

## 4. Cuenta propia: `GET /api/account`

Requiere `Authorization: Bearer <jwt>` con `ROLE_USER` o `ROLE_ADMIN`. No recibe ningún parámetro: el usuario sale del `sub` del token ya validado, así que nadie puede pedir la cuenta de otro (un `?login=` o un `?id=` se ignora). Respuesta `200 OK` con la misma forma que el registro, sin contraseña ni hash. Si el usuario del token ya no existe o no está activo, `401`.

### 4.1 Qué valida cronos de un token

Solo RS256 (un token `HS256` o `none` se rechaza), la firma, el vencimiento con una tolerancia de reloj de 60 segundos y los claims `sub` y `exp` obligatorios. Las autoridades salen del claim `auth`. Un cambio de rol en la base no se ve en un token ya emitido hasta que vence.

### 4.2 CORS

Sin orígenes configurados no se acepta ninguno. Con una lista (`esquema://host[:puerto]`, sin comodines) se aceptan solo esos, con `GET`, `POST` y `OPTIONS`, los encabezados `Authorization`, `Content-Type` y `Accept`, y sin credenciales. La app Android no es un navegador y no lo necesita.

## 5. Errores

| Situación | HTTP | `code` |
|---|---|---|
| Falta un campo, formato o largo inválido, o JSON ilegible | 400 | `VALIDATION_ERROR` (con `fieldErrors` en los errores de campo) |
| En el registro, la contraseña presente fuera de 4 a 100 y nada más falla | 400 | `INVALID_PASSWORD` |
| Login ya usado | 400 | `USERNAME_ALREADY_EXISTS` |
| Email ya usado | 400 | `EMAIL_ALREADY_EXISTS` |
| Login inexistente, contraseña equivocada o usuario no activo | 401 | `INVALID_CREDENTIALS` (siempre el mismo cuerpo) |
| Sin token, token mal formado, vencido, alterado, de otra clave, de otro algoritmo o sin `exp`, o de un usuario que ya no existe o no está activo | 401 | `NO_AUTENTICADO` (con `WWW-Authenticate: Bearer`) |
| Token válido pero sin el rol que pide la ruta | 403 | `SIN_PERMISO` |
| Ruta o método no habilitados, con token válido | 403 | `SIN_PERMISO` |
| Ruta o método no habilitados, sin token | 401 | `NO_AUTENTICADO` |
| Base de datos no disponible | 503 | `SERVICE_UNAVAILABLE` |

Forma del error: `title`, `status`, `message`, `path` y `code`, como en la referencia de integración (sección 13). Los mensajes son fijos: **no repiten** el valor recibido, y menos una contraseña. El `401` y el `403` **no dicen por qué** falló el token y nunca lo repiten; sus códigos son los mismos que usa atlas.

Los vocabularios `VALIDATION_ERROR`, `USERNAME_ALREADY_EXISTS`, `EMAIL_ALREADY_EXISTS` e `INVALID_PASSWORD` salen de la matriz de errores de la cátedra para el registro de la cuenta técnica (13.1); el enunciado no define validaciones propias para el usuario final, así que se reutilizan como referencia.

## 6. Lo que todavía no está

- Cierre del issue #33 de atlas: la prueba cruzada ya se hizo (un token real de cronos fue aceptado por atlas, [evidencia](../evidencias/isla-2-prueba-cruzada.md)) y falta que el alumno lo cierre.
- Un usuario administrador (`ROLE_ADMIN`): el registro solo crea `ROLE_USER`.
- Recuperación de contraseña, edición del perfil, límite de intentos de login y revocación de tokens.
