# Implementación de cronos-turnos · evolución

**Componente:** cronos-turnos · **Isla:** 2 · Ogigia (arranque anticipado) · **Actualizado:** 2026-11-21 (holds)

Registra cómo se construyó el código, en orden, y qué se decidió al implementar. Stack igual al de atlas ([ADR 0002](../arquitectura/adr/0002-stack.md)); arquitectura interna igual ([ADR 0003](../arquitectura/adr/0003-arquitectura.md)); usuarios sin JHipster ([ADR 0005](../arquitectura/adr/0005-usuarios-y-jwt-en-cronos-sin-jhipster.md)).

## Línea de tiempo

| Fecha | Issue / PR | Qué se hizo | Estado |
|---|---|---|---|
| 2026-10-03 y 04 | #1 a #4 | Estructura inicial, `.env.example`, PostgreSQL con Docker Compose | Cerrados |
| 2026-11-19 | #5 · PR #6 | Esqueleto: Spring Boot 4.1.1, Java 25, puerto 8081, Flyway sin tablas, ArchUnit y test de contexto. Aprobado por el docente en GitHub | Cerrado, mergeado a `dev` (`2f578c6`) |
| 2026-11-19 a 21 | #7 · PR #8 | Registro, login y emisión del JWT RS256, rutas protegidas y prueba cruzada con atlas. Etapas 1 a 6 | Mergeado a `dev` (`a631eb0`); el issue se cierra a mano |
| 2026-11-21 | #9 · PR #10 | Disponibilidad de turnos: horarios de atlas menos ocupaciones de la cátedra | Mergeado a `dev` (`dadfdbd`); el issue se cierra a mano |
| 2026-11-21 | #11 · rama `feature/holds` | Iniciar una reserva: hold y confirmación inicial con estado local y propiedad por usuario | En curso (rama pusheada; PR pendiente) |

## Usuarios y JWT (issue #7), etapas 1 a 6

Un commit por etapa. Las etapas 1 a 3 se publicaron el 2026-11-19; la 4, la 5 y la 6 son locales hasta que se pida el push.

1. **Base de usuarios** (`f160bc3`). Migración `V1__usuarios.sql` ([modelo](../modelo-datos/cronos-turnos.md)), usuario de dominio que nace activo y con `ROLE_USER`, puerto `UserRepository` y su adaptador sobre Spring Data. La seguridad deja público solo `/actuator/health`.
2. **Registro** (`6dad760`, `8d622b6`). Caso de uso `RegisterUser`, hash de contraseña detrás del puerto `PasswordHasher`, `POST /api/register` y los errores `problem+json`.
3. **Login y token** (`fb43e3f`). Caso de uso `AuthenticateUser`, puerto `TokenIssuer` con `NimbusTokenIssuer` (RS256), `POST /api/authenticate` y la carga de la clave privada.
4. **Seguridad de las rutas** (`be39029`). Cronos valida los tokens que emite con la clave pública derivada de su privada (`JwtKeyPair`): solo RS256, vencimiento con tolerancia de reloj de 60 s y `sub` y `exp` obligatorios; las autoridades salen del claim `auth`. `GET /api/account` (caso de uso `GetAccount`) devuelve la cuenta del dueño del token. `SecurityProblemHandler` responde `401 NO_AUTENTICADO` y `403 SIN_PERMISO` como `problem+json`, con los mismos códigos que atlas. CORS por lista de orígenes. 36 pruebas nuevas.
5. **Prueba cruzada con atlas** (`2b2966d`). `scripts/recorrido-cliente.sh` simula el recorrido de un cliente con `curl` contra los dos servicios corriendo: 26 de 26 comprobaciones bien. Un token real de cronos fue aceptado por atlas. [Evidencia](../evidencias/isla-2-prueba-cruzada.md).
6. **Documentación** (`b96f08c` y esta biblioteca). README de cronos al día, contrato con `GET /api/account` y los `401`/`403`, evidencia de la prueba cruzada y regla de ArchUnit sin paquetes vacíos.

Capas (hexagonal liviana, como atlas): `domain` solo con el JDK; `application` con los casos de uso y los puertos (`UserRepository`, `PasswordHasher`, `TokenIssuer`); `adapters.in.web`, `adapters.out.persistence` y `adapters.out.security`; `config` con el cableado. La regla de ArchUnit impide que `application` use Spring Security, por eso el hash y el JWT van detrás de puertos.

## Disponibilidad (issue #9)

`GET /api/professionals/{id}/availability?from=&to=` ([contrato](../contratos/cronos-turnos-api.md), sección 5). Capas, igual que en usuarios:

- **`domain`**: `WeeklySchedule`, `ProfessionalAgenda`, `Occupancy`, `Slot` y `AvailabilityCalculator`, una función pura (grilla, turnos que no entran completos, ocupaciones, turnos que ya empezaron, horarios superpuestos y duraciones inválidas). Solo usa el JDK.
- **`application`**: el caso de uso `GetAvailability` y dos puertos de salida, `CatalogClient` (atlas) y `OccupancyClient` (cátedra), con sus excepciones. El caso de uso valida el rango, pide atlas, y solo si el profesional atiende en el rango pregunta a la cátedra, una vez para todo el rango.
- **`adapters.out.rest`**: `AtlasCatalogClient` y `CatedraOccupancyClient` sobre `RestClient`, con timeouts, reintentos acotados y sin redirecciones.
- **`adapters.in.web`**: `AvailabilityController` y los `problem+json` nuevos.
- **`config`**: `AtlasProperties`, `CatedraProperties` (las mismas variables `CATEDRA_*` que atlas, ahora obligatorias), `AvailabilityProperties` y el cableado.

| Decisión | Motivo |
|---|---|
| Orden: atlas primero; si falla, no se consulta a la cátedra | Sin catálogo no se puede validar la información vigente (enunciado 8); no hay que gastar una llamada que no puede usarse. |
| Si el profesional no atiende en el rango, no se consulta a la cátedra | No hay turnos que restar. |
| Una sola consulta de ocupaciones por rango, no una por día | Menos llamadas a un servicio externo y menos puntos donde fallar. |
| Se reenvía el JWT del usuario a atlas y el técnico solo va a la cátedra | Atlas debe saber quién consulta; la cuenta técnica es otra identidad y nunca sale de cronos (enunciado 3.2). Hay una prueba de cada lado. |
| Un estado de ocupación desconocido hace fallar la consulta | Ofrecer un turno que podría estar tomado es peor que decir que no se puede calcular. |
| Los reintentos van de 0 a 5 y solo para lecturas transitorias | El enunciado pide evitar ciclos de reintento ilimitados (sección 8). |
| No se siguen redirecciones | Un token no se reenvía a otro destino. |
| Los turnos pasados se descartan en la hora local del consultorio (`CRONOS_CLINIC_ZONE`) | Los horarios no traen zona (referencia, sección 4); se fija una por configuración, con Buenos Aires por defecto. **Es una decisión propia**: la cátedra no define la zona. |
| `503` con un código propio por cada servicio caído (`CATALOG_UNAVAILABLE`, `CATEDRA_UNAVAILABLE`) | El cliente y el log distinguen quién falló sin exponer detalles. |

**Lo que encontraron las pruebas:** la prueba de punta a punta falló todas las veces la primera vez porque el inicializador de pruebas (que pone una cátedra falsa para que cronos arranque) pisaba a los servidores simulados de la propia prueba; y un `@ContextConfiguration` directo en una clase **reemplaza** al de la meta-anotación en lugar de sumarse, así que el inicializador de la clave JWT dejó de correr. Una mutación escrita mal (`|| false`) no cambió nada y se repitió bien.

**Pruebas:** 214 en verde (92 nuevas): el calculador (22), el caso de uso con dobles (14), los dos clientes contra HTTP real (12 y 11), la configuración de los clientes con timeouts y redirecciones (6 y 5 de propiedades) y la API de punta a punta con PostgreSQL y servidores simulados (22). Seis mutaciones deliberadas fueron detectadas (no restar `HELD`, ofrecer turnos que ya empezaron, aceptar turnos que no entran, seguir redirecciones, consultar a la cátedra sin grilla y dejar la ruta pública). Evidencia: [isla-2-disponibilidad](../evidencias/isla-2-disponibilidad.md), con una corrida con la cátedra simulada y otra con **la cátedra real** (formato de las ocupaciones confirmado y un turno `CONFIRMED` real restado).

## Holds: iniciar una reserva (issue #11)

`POST /api/reservations` ([contrato](../contratos/cronos-turnos-api.md), sección 6; [modelo de datos](../modelo-datos/cronos-turnos.md), tabla `reservation_process`).

- **`domain`**: `ReservationStatus` (la máquina de estados, donde un estado final no retrocede) y `Reservation` (inmutable: cada cambio devuelve otro valor y exige una transición permitida).
- **`application`**: el caso de uso `StartReservation` y los puertos `HoldGateway` (la cátedra), `ReservationRepository` y `CatalogClient`; excepciones propias (`CatedraRejectedException` frente a `CatedraUnavailableException`).
- **`adapters.out.rest`**: `CatedraHoldClient`, **sin reintentos automáticos**.
- **`adapters.out.persistence`**: `ReservationEntity` (con `@Version`), `JpaReservationRepository` y la migración `V2__reservas.sql`.
- **`adapters.in.web`**: `ReservationController`, `ReservationRequest`, `ReservationResponse` y los `problem+json` nuevos.

| Decisión | Motivo |
|---|---|
| El proceso se guarda **antes** de cada llamada con efectos y nunca dentro de una transacción mientras se espera a la red | Si cronos se corta queda el rastro; una transacción abierta durante una llamada de red agota conexiones. |
| Los holds no se reintentan solos | Tienen efectos y un timeout no prueba que fallaron (referencia 18.4). |
| Distinguir un **rechazo** de la cátedra (por `status` y `code`) de **no saber qué pasó** | Se tratan distinto: un rechazo cierra el proceso con su motivo; no saber deja la decisión a la reconciliación. |
| Si no se sabe si el hold se creó, el proceso se cierra como `FAILED` | No queda colgado; el hold, si existe, vence solo. Costo: el turno puede figurar como ocupado hasta que venza. |
| Si no se sabe si se confirmó, se reconcilia **una** vez y se deja en `HELD` | Repetir la confirmación es seguro (`RESERVATION_PROCESS_ALREADY_CONFIRMED` cuenta como éxito); repetir el pedido retoma sin crear otro hold. |
| Pedir dos veces lo mismo reutiliza el proceso activo; el índice único parcial lo impide ante dos pedidos a la vez | "Sin reservas duplicadas" (enunciado 7). |
| La cátedra conoce al paciente como `user-<id>` | Un identificador opaco: no revela el login a un servicio externo. |
| No se pregunta a la cátedra si el turno está libre antes de pedir el hold | La respuesta del hold (`SLOT_ALREADY_HELD` / `SLOT_ALREADY_RESERVED`) es la verdad; una consulta previa sería otra foto que se queda vieja. |
| Los instantes (`expiresAt`, `createdAt`, `updatedAt`) se truncan a microsegundos **en el dominio** | Lo que se devuelve al guardar es idéntico a lo que se lee después de la base. La cátedra real informa el vencimiento con nanosegundos y PostgreSQL guarda microsegundos. |
| Un proceso activo que ya pasó su `expiresAt` se cierra como `EXPIRED` al volver a pedir el turno | Con la cátedra real el hold vence solo y cronos, sin Kafka todavía, no se entera: sin esta regla el usuario recibiría un proceso que ya no existe. La recuperación completa es el #13 y el evento de expiración, el #15. |
| Un rechazo que no debería ocurrir (paciente que no coincide, hold de otra cuenta, cuerpo rechazado) da `502 CATEDRA_ERROR` sin detalle | Es un error de cronos o de configuración, no del usuario; queda en el log. |

**Lo que encontró el hold real** (los dobles de las pruebas no lo habían mostrado): (a) la cátedra informa `expiresAt` con **nanosegundos** (`17:02:25.905856025Z`) y la base guarda microsegundos, así que la primera respuesta de un pedido y las siguientes difería: se corrigió truncando en el dominio, con una prueba que falla sin la corrección. (b) El hold **vence solo** y cronos no se entera todavía: el usuario recibía un proceso muerto al reintentar; se agregó la regla de vencimiento local.

**Lo que encontraron las pruebas:** (1) un pedido repetido devolvía `createdAt` con nanosegundos la primera vez y con microsegundos la segunda (la base trunca). (2) La prueba de "ningún dato personal en los logs" falló porque con todo en `TRACE`, Hibernate y el driver de PostgreSQL escriben los valores que enlazan al SQL, **incluido el nombre del paciente**. Es un límite del mismo tipo que el del *rejected value* de Spring: ninguna clase de cronos lo escribe y los tokens no aparecen en ninguna parte, pero queda documentado.

**Evidencia con la cátedra real:** [isla-2-holds](../evidencias/isla-2-holds.md).

**Pruebas:** 325 en verde (111 nuevas): los estados y sus transiciones (`ReservationStatusTest`, `ReservationTest`), el caso de uso con dobles (30), el cliente de holds contra HTTP real (11), su configuración (4), el repositorio contra PostgreSQL (18: índice único parcial, versiones, `CHECK`, claves) y la API de punta a punta (22). Diez mutaciones deliberadas fueron detectadas (las dos últimas, del vencimiento local y de la precisión): no cerrar el proceso al rechazarse el hold, no reutilizar el proceso activo, mandar el login a la cátedra, no reconciliar la confirmación, no tomar `RESERVATION_PROCESS_ALREADY_CONFIRMED` como éxito, permitir que un estado final reviva, un índice único sin la condición de activos y la ruta sin autenticación.

## Decisiones al implementar (usuarios)

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

(Al cerrar usuarios.) 122 pruebas en verde, sin fallas ni errores, contra PostgreSQL real con Testcontainers: las 86 de las etapas 1 a 3 (dominio, casos de uso con dobles, migración y restricciones, hash, emisión y verificación del token, carga de claves, arranque sin clave y la API de punta a punta con prueba de que la contraseña no aparece en respuestas ni logs) y 36 nuevas de la etapa 4 (`GET /api/account`, tokens malos, `401` y `403`, rutas públicas con encabezado roto, CORS y configuración). Cuatro mutaciones deliberadas fueron detectadas por una prueba: quitar el hash de relleno, meter el email en el token, no exigir `sub` y `exp`, y abrir `/api/account` a cualquier autenticado. Evidencia con la aplicación real: [isla-2-usuarios-jwt](../evidencias/isla-2-usuarios-jwt.md) y [isla-2-prueba-cruzada](../evidencias/isla-2-prueba-cruzada.md).

## Límites y lo que sigue

- Sin límite de intentos de login ni revocación de tokens; mínimo de contraseña de 4 (el de la cátedra); los roles salen del token; rotar la clave invalida todos los tokens y exige reiniciar atlas.
- La prueba cruzada es un script manual, no una prueba automática que corra en cada build.
- Falta: el cierre del issue #7 y del #33 de atlas, y un usuario administrador (`ROLE_ADMIN`) para la demostración.
- Después: reservas con Kafka e idempotencia (#15), consulta y cancelación de reservas propias (#12), recuperación al reiniciar (#13) y usuario administrador (#14).
