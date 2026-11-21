# Implementación de cronos-turnos · evolución

**Componente:** cronos-turnos · **Isla:** 2 · Ogigia (arranque anticipado) · **Actualizado:** 2026-11-21

Registra cómo se construyó el código, en orden, y qué se decidió al implementar. Stack igual al de atlas ([ADR 0002](../arquitectura/adr/0002-stack.md)); arquitectura interna igual ([ADR 0003](../arquitectura/adr/0003-arquitectura.md)); usuarios sin JHipster ([ADR 0005](../arquitectura/adr/0005-usuarios-y-jwt-en-cronos-sin-jhipster.md)).

## Línea de tiempo

| Fecha | Issue / PR | Qué se hizo | Estado |
|---|---|---|---|
| 2026-10-03 y 04 | #1 a #4 | Estructura inicial, `.env.example`, PostgreSQL con Docker Compose | Cerrados |
| 2026-11-19 | #5 · PR #6 | Esqueleto: Spring Boot 4.1.1, Java 25, puerto 8081, Flyway sin tablas, ArchUnit y test de contexto. Aprobado por el docente en GitHub | Cerrado, mergeado a `dev` (`2f578c6`) |
| 2026-11-19 a 21 | #7 · rama `feature/usuarios-jwt` | Registro, login y emisión del JWT RS256, rutas protegidas y prueba cruzada con atlas. Etapas 1 a 6 hechas | Abierto; falta el PR a `dev` |

## Usuarios y JWT (issue #7), etapas 1 a 6

Un commit por etapa. Las etapas 1 a 3 se publicaron el 2026-11-19; la 4, la 5 y la 6 son locales hasta que se pida el push.

1. **Base de usuarios** (`f160bc3`). Migración `V1__usuarios.sql` ([modelo](../modelo-datos/cronos-turnos.md)), usuario de dominio que nace activo y con `ROLE_USER`, puerto `UserRepository` y su adaptador sobre Spring Data. La seguridad deja público solo `/actuator/health`.
2. **Registro** (`6dad760`, `8d622b6`). Caso de uso `RegisterUser`, hash de contraseña detrás del puerto `PasswordHasher`, `POST /api/register` y los errores `problem+json`.
3. **Login y token** (`fb43e3f`). Caso de uso `AuthenticateUser`, puerto `TokenIssuer` con `NimbusTokenIssuer` (RS256), `POST /api/authenticate` y la carga de la clave privada.
4. **Seguridad de las rutas** (`be39029`). Cronos valida los tokens que emite con la clave pública derivada de su privada (`JwtKeyPair`): solo RS256, vencimiento con tolerancia de reloj de 60 s y `sub` y `exp` obligatorios; las autoridades salen del claim `auth`. `GET /api/account` (caso de uso `GetAccount`) devuelve la cuenta del dueño del token. `SecurityProblemHandler` responde `401 NO_AUTENTICADO` y `403 SIN_PERMISO` como `problem+json`, con los mismos códigos que atlas. CORS por lista de orígenes. 36 pruebas nuevas.
5. **Prueba cruzada con atlas** (`2b2966d`). `scripts/recorrido-cliente.sh` simula el recorrido de un cliente con `curl` contra los dos servicios corriendo: 26 de 26 comprobaciones bien. Un token real de cronos fue aceptado por atlas. [Evidencia](../evidencias/isla-2-prueba-cruzada.md).
6. **Documentación** (`b96f08c` y esta biblioteca). README de cronos al día, contrato con `GET /api/account` y los `401`/`403`, evidencia de la prueba cruzada y regla de ArchUnit sin paquetes vacíos.

Capas (hexagonal liviana, como atlas): `domain` solo con el JDK; `application` con los casos de uso y los puertos (`UserRepository`, `PasswordHasher`, `TokenIssuer`); `adapters.in.web`, `adapters.out.persistence` y `adapters.out.security`; `config` con el cableado. La regla de ArchUnit impide que `application` use Spring Security, por eso el hash y el JWT van detrás de puertos.

## Decisiones al implementar

| Decisión | Motivo |
|---|---|
| Hash = SHA-256 (Base64) + BCrypt | BCrypt lanza una excepción con más de 72 bytes y el contrato permite 100 caracteres (200 bytes con tildes). Recortar sería peor: dos contraseñas con los mismos 72 bytes iniciales serían iguales. |
| Misma excepción y mismo `401` para login inexistente, contraseña equivocada y usuario no activo, con un hash de relleno cuando el login no existe | No revelar qué logins existen, ni por el mensaje ni por el tiempo. |
| Login y email en minúsculas, también como `CHECK` de la base | La unicidad no puede depender de las mayúsculas. |
| La clave privada se carga por archivo o variable y la pública se **deriva** de ella | Una sola variable; cronos valida sus propios tokens sin otra clave. Sin clave la aplicación no arranca, como atlas sin la pública. |
| Contraseña máxima de 100 también en el login | Acota el trabajo de hash que puede pedir un cliente. |
| `INVALID_PASSWORD` solo en el registro | Es el code de la cátedra para el registro (13.1); el login responde `VALIDATION_ERROR`. |
| Las pruebas generan la clave RSA al vuelo | No hay ninguna clave en el repo, ni siquiera de prueba. |
| Las rutas públicas ignoran el encabezado `Authorization` | Un cliente con un token vencido guardado, si lo mandara a `/api/authenticate`, recibiría `401` de una ruta que no necesita token y no podría volver a entrar. |
| `GET /api/account` no recibe ningún identificador: el usuario sale del `sub` del token ya validado | Nadie puede pedir la cuenta de otro. Se probó mandando `?login=admin&id=1`: sigue devolviendo la cuenta propia. |
| Los roles salen del token, la cuenta sale de la base | Es lo que hace atlas y evita una consulta por pedido; el costo es que un cambio de rol no se ve hasta que el token vence (límite conocido). |
| Token válido de un usuario que ya no existe o no está activo: `401` en `/api/account` | Es lo único que invalida un token antes de que venza. |
| Una ruta no habilitada, sin token, da `401` (antes `403`) | Sin token no se sabe quién es; el `403` queda para quien se identificó y no tiene permiso. |
| El rechazo no dice por qué falló el token y el log nunca lo registra | No ayudar a quien prueba tokens, y no dejar tokens en los logs. |
| CORS vacío = ningún origen; con lista, solo `GET`, `POST` y `OPTIONS`, sin credenciales | La app Android no es un navegador y no lo necesita; la lista es para una eventual web. |

## Lo que encontraron las pruebas

- **BCrypt y los 72 bytes.** Una prueba con la contraseña máxima del contrato (100 caracteres) falló con una excepción. Es la razón del prehash.
- **Una prueba de logs vacía.** La primera "la contraseña no aparece en los logs" pasaba porque la aplicación no escribe nada en esas peticiones. Se subieron los niveles de log (seguridad, SQL con parámetros y código propio) y se exige que haya salida; con eso la prueba mira algo.
- **Un límite que no se puede cerrar sin envolver la contraseña:** en `DEBUG` o `TRACE` de `org.springframework.web`, Spring escribe el *rejected value* de una validación fallida, y eso incluye la contraseña cuando es ella la que no cumple el largo. Con la configuración normal no se escribe. Está en el README de cronos como límite conocido.
- **El nivel de log es global a la JVM.** Una clase de prueba podía dejar los niveles bajos y hacer que la prueba de logs de otra pasara vacía. Ahora cada caso fija los niveles antes de correr (`LogLevels`).
- **Una regla de arquitectura que no miraba nada.** `ArquitecturaTest` admitía paquetes vacíos porque al arrancar no había clases; con las clases ya presentes se quitó `allowEmptyShould`, para que si se vaciaran o renombraran los paquetes la regla falle en lugar de pasar.

## Pruebas

122 pruebas en verde, sin fallas ni errores, contra PostgreSQL real con Testcontainers: las 86 de las etapas 1 a 3 (dominio, casos de uso con dobles, migración y restricciones, hash, emisión y verificación del token, carga de claves, arranque sin clave y la API de punta a punta con prueba de que la contraseña no aparece en respuestas ni logs) y 36 nuevas de la etapa 4 (`GET /api/account`, tokens malos, `401` y `403`, rutas públicas con encabezado roto, CORS y configuración). Cuatro mutaciones deliberadas fueron detectadas por una prueba: quitar el hash de relleno, meter el email en el token, no exigir `sub` y `exp`, y abrir `/api/account` a cualquier autenticado. Evidencia con la aplicación real: [isla-2-usuarios-jwt](../evidencias/isla-2-usuarios-jwt.md) y [isla-2-prueba-cruzada](../evidencias/isla-2-prueba-cruzada.md).

## Límites y lo que sigue

- Sin límite de intentos de login ni revocación de tokens; mínimo de contraseña de 4 (el de la cátedra); los roles salen del token; rotar la clave invalida todos los tokens y exige reiniciar atlas.
- La prueba cruzada es un script manual, no una prueba automática que corra en cada build.
- Falta: que el PR llegue a `dev`, el cierre del issue #33 de atlas y un usuario administrador (`ROLE_ADMIN`) para la demostración.
- Después: cliente de atlas y disponibilidad, bloqueos con vencimiento, reservas con Kafka e idempotencia, y un usuario administrador si hace falta para la demostración.
