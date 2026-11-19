# Modelo de datos de cronos-turnos (usuarios)

**Estado:** implementado en la migración `V1__usuarios.sql` (2026-11-19, issue #7 de cronos-turnos). Cuando se agreguen los bloqueos y las reservas, este documento crece con sus tablas.

## Alcance y propiedad

- `cronos-turnos` es el único propietario de estas tablas, en su propia base (PostgreSQL, puerto 5434 en local). Atlas no las toca: solo valida el token.
- Flyway es el dueño del esquema; Hibernate solo valida (`ddl-auto=validate`). Una migración ya aplicada no se edita.

## Tablas

### `app_user`

| Columna | Tipo | Reglas |
|---|---|---|
| `id` | `bigint` identidad | PK; lo genera la base. |
| `login` | `varchar(50)` | NOT NULL, único, en minúsculas, mínimo 3 caracteres. |
| `password_hash` | `varchar(100)` | NOT NULL. Hash BCrypt (60 caracteres hoy); la columna deja lugar a otro algoritmo. |
| `first_name`, `last_name` | `varchar(50)` | Opcionales. |
| `email` | `varchar(254)` | Opcional, único si se informa (varios `NULL` conviven), en minúsculas. |
| `image_url` | `varchar(256)` | Opcional. |
| `lang_key` | `varchar(10)` | NOT NULL, por defecto `es`. |
| `activated` | `boolean` | NOT NULL. Nace en `true`. |
| `created_at`, `updated_at` | `timestamptz` | NOT NULL; los pone el backend. |

### `user_authority`

| Columna | Tipo | Reglas |
|---|---|---|
| `user_id` | `bigint` | FK a `app_user(id)`, `ON DELETE CASCADE`. |
| `authority` | `varchar(50)` | Formato `ROLE_[A-Z_]+`. |
| | | PK compuesta (`user_id`, `authority`). |

Es el nombre `app_user` y no `user` porque `user` es palabra reservada en PostgreSQL.

## Decisiones

- **Las reglas del dominio se repiten como `CHECK`.** Login y email en minúsculas y el largo mínimo del login los garantiza el dominio, y la base los rechaza si una escritura se lo salta: no se guarda un duplicado disfrazado por mayúsculas.
- **Compatible con el usuario de JHipster en lo observable** (enunciado 3.2): mismos datos y comportamiento, no mismos nombres de tabla.
- **La contraseña nunca se guarda en claro.** Se reduce con SHA-256 (Base64) y se aplica BCrypt, porque BCrypt no admite más de 72 bytes y el contrato permite 100 caracteres.
- **Sin borrado ni edición de usuarios todavía.** No hay endpoints para eso; la cascada de `user_authority` es solo coherencia.
