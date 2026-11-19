# Implementación de cronos-turnos · evolución

**Componente:** cronos-turnos · **Isla:** 2 · Ogigia (arranque anticipado) · **Actualizado:** 2026-11-19

Registra cómo se construyó el código, en orden, y qué se decidió al implementar. Stack igual al de atlas ([ADR 0002](../arquitectura/adr/0002-stack.md)); arquitectura interna igual ([ADR 0003](../arquitectura/adr/0003-arquitectura.md)); usuarios sin JHipster ([ADR 0005](../arquitectura/adr/0005-usuarios-y-jwt-en-cronos-sin-jhipster.md)).

## Línea de tiempo

| Fecha | Issue / PR | Qué se hizo | Estado |
|---|---|---|---|
| 2026-10-03 y 04 | #1 a #4 | Estructura inicial, `.env.example`, PostgreSQL con Docker Compose | Cerrados |
| 2026-11-19 | #5 · PR #6 | Esqueleto: Spring Boot 4.1.1, Java 25, puerto 8081, Flyway sin tablas, ArchUnit y test de contexto. Aprobado por el docente en GitHub | Cerrado, mergeado a `dev` (`2f578c6`) |
| 2026-11-19 | #7 · rama `feature/usuarios-jwt` | Registro, login y emisión del JWT RS256. Etapas 1 a 3 hechas; faltan la 4 (rutas protegidas) a la 6 (documentación) | Abierto, sin PR |

## Usuarios y JWT (issue #7), etapas 1 a 3

Un commit por etapa, todo publicado en la rama.

1. **Base de usuarios** (`f160bc3`). Migración `V1__usuarios.sql` ([modelo](../modelo-datos/cronos-turnos.md)), usuario de dominio que nace activo y con `ROLE_USER`, puerto `UserRepository` y su adaptador sobre Spring Data. La seguridad deja público solo `/actuator/health`.
2. **Registro** (`6dad760`, `8d622b6`). Caso de uso `RegisterUser`, hash de contraseña detrás del puerto `PasswordHasher`, `POST /api/register` y los errores `problem+json`.
3. **Login y token** (`fb43e3f`). Caso de uso `AuthenticateUser`, puerto `TokenIssuer` con `NimbusTokenIssuer` (RS256), `POST /api/authenticate` y la carga de la clave privada.

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

## Lo que encontraron las pruebas

- **BCrypt y los 72 bytes.** Una prueba con la contraseña máxima del contrato (100 caracteres) falló con una excepción. Es la razón del prehash.
- **Una prueba de logs vacía.** La primera "la contraseña no aparece en los logs" pasaba porque la aplicación no escribe nada en esas peticiones. Se subieron los niveles de log (seguridad, SQL con parámetros y código propio) y se exige que haya salida; con eso la prueba mira algo.
- **Un límite que no se puede cerrar sin envolver la contraseña:** en `DEBUG` o `TRACE` de `org.springframework.web`, Spring escribe el *rejected value* de una validación fallida, y eso incluye la contraseña cuando es ella la que no cumple el largo. Con la configuración normal no se escribe. Está en el README de cronos como límite conocido.

## Pruebas

86 pruebas en verde, sin fallas ni errores, contra PostgreSQL real con Testcontainers: dominio, casos de uso con dobles, migración y restricciones, hash, emisión y verificación del token (alterado, firmado con otra clave, vencido), carga de claves, arranque sin clave y la API de punta a punta (con prueba de que la contraseña no aparece en respuestas ni logs). Dos mutaciones deliberadas (quitar el hash de relleno y meter el email en el token) fueron detectadas por una prueba. Evidencia con la aplicación real: [isla-2-usuarios-jwt](../evidencias/isla-2-usuarios-jwt.md).

## Límites y lo que sigue

- Sin límite de intentos de login ni revocación de tokens; mínimo de contraseña de 4 (el de la cátedra).
- Falta: validar los tokens propios y `GET /api/account` (etapa 4), la prueba cruzada con atlas y el cierre del issue #33 (etapa 5), y que el PR llegue a `dev`.
- Después: cliente de atlas y disponibilidad, bloqueos con vencimiento, reservas con Kafka e idempotencia, y un usuario administrador si hace falta para la demostración.
