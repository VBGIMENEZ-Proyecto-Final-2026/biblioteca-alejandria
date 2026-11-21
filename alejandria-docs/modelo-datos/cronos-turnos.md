# Modelo de datos de cronos-turnos (usuarios y reservas)

**Estado:** usuarios en la migración `V1__usuarios.sql` (2026-11-19, issue #7) y procesos de reserva en `V2__reservas.sql` (2026-11-21, issue #11 de cronos-turnos). Cuando se agregue Kafka (issue #15), este documento suma la tabla de eventos procesados.

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

### `reservation_process` (V2)

Un proceso de reserva de un usuario: el turno que pidió, cómo lo conoce la cátedra y en qué estado va. **Cronos no guarda el catálogo**: el nombre del profesional es una foto descriptiva de cuando se reservó, no el dato vigente (enunciado 4.2).

| Columna | Tipo | Notas |
|---|---|---|
| `id` | `bigint` | Clave primaria; la genera la base (`GENERATED ALWAYS`): nadie inserta un id a mano. |
| `user_id` | `bigint` | **Dueño del proceso.** FK a `app_user(id)` sin `ON DELETE`: no se borra un usuario que tiene reservas. |
| `reservation_process_id`, `hold_id` | `varchar(100)` | Cómo los llama la cátedra. `NULL` hasta que existe el hold; cada uno es `UNIQUE`. |
| `professional_id` | `bigint` | Id del profesional en el catálogo (atlas). |
| `professional_first_name`, `professional_last_name` | `varchar(100)` | Foto histórica, opcional. |
| `appointment_date`, `start_time`, `end_time` | `date`, `time`, `time` | El turno. `end_time > start_time` (`CHECK`). |
| `patient_first_name`, `patient_last_name` | `varchar(100)` | Lo que el usuario escribió para la cátedra (2 a 100, validado antes de guardar). **Dato personal.** |
| `status` | `varchar(30)` | Uno de `STARTING`, `HELD`, `WAITING_FOR_PHONE`, `CONFIRMED`, `REJECTED`, `EXPIRED`, `INVALID`, `CANCELLED`, `FAILED` (`CHECK`). |
| `expires_at` | `timestamptz` | Vencimiento del hold o del proceso, el que informó la cátedra. |
| `failure_code` | `varchar(60)` | Motivo estable de una falla (el nombre de un código), nunca un texto de la cátedra ni un dato del usuario. |
| `version` | `bigint` | Bloqueo optimista: dos escrituras simultáneas sobre el mismo proceso no se pisan. |
| `created_at`, `updated_at` | `timestamptz` | |

Restricciones que importan:
- **Índice único parcial `reservation_process_active_slot`** sobre (`user_id`, `professional_id`, `appointment_date`, `start_time`) para los estados `STARTING`, `HELD`, `WAITING_FOR_PHONE` y `CONFIRMED`: un usuario no puede tener dos procesos activos para el mismo turno. Pedir dos veces lo mismo (o dos pedidos a la vez) no crea dos holds. Los procesos terminados mal o cerrados no cuentan, para poder volver a intentar. Otro usuario sí puede pedir el mismo turno: la cátedra decide quién lo toma.
- `CHECK reservation_process_hold_known`: un proceso que ya tiene hold (cualquier estado menos `STARTING` y `FAILED`) sabe cómo lo llama la cátedra.
- Índice (`user_id`, `created_at DESC`) para "mis reservas".

**Máquina de estados** (implementada en `ReservationStatus`; un estado final no retrocede):

| Desde | Puede pasar a |
|---|---|
| `STARTING` | `HELD`, `FAILED` |
| `HELD` | `WAITING_FOR_PHONE`, `EXPIRED`, `INVALID`, `FAILED` |
| `WAITING_FOR_PHONE` | `CONFIRMED`, `REJECTED`, `EXPIRED`, `INVALID`, `FAILED` |
| `CONFIRMED` | `CANCELLED` |
| `REJECTED`, `EXPIRED`, `INVALID`, `CANCELLED`, `FAILED` | nada (finales) |

## Decisiones

- **Se guarda el proceso antes de cada paso con efectos.** `STARTING` queda registrado antes de pedir el hold: si cronos se corta, el rastro existe (la recuperación al reiniciar es el issue #13).
- **La propiedad por usuario vive en esta tabla**, no en la cátedra: la cátedra solo conoce la cuenta técnica del proyecto y a cada paciente como `user-<id>`, un identificador opaco que no revela el login (enunciado 4.2 y 9).
- **Sin ON DELETE sobre `user_id`.** Borrar un usuario borraría sus reservas; como no hay borrado de usuarios, se prefiere que la base lo impida.

- **Las reglas del dominio se repiten como `CHECK`.** Login y email en minúsculas y el largo mínimo del login los garantiza el dominio, y la base los rechaza si una escritura se lo salta: no se guarda un duplicado disfrazado por mayúsculas.
- **Compatible con el usuario de JHipster en lo observable** (enunciado 3.2): mismos datos y comportamiento, no mismos nombres de tabla.
- **La contraseña nunca se guarda en claro.** Se reduce con SHA-256 (Base64) y se aplica BCrypt, porque BCrypt no admite más de 72 bytes y el contrato permite 100 caracteres.
- **Sin borrado ni edición de usuarios todavía.** No hay endpoints para eso; la cascada de `user_authority` es solo coherencia.
