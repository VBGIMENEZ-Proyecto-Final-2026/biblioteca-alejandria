# ADR 0005 · Usuarios y JWT en cronos-turnos: Spring Security a mano, sin JHipster y con el contrato de usuario de JHipster

**Estado:** aceptado por el alumno el 2026-11-19 y implementado en `cronos-turnos` (issue #7, etapas 1 a 6: registro, login con JWT RS256, rutas protegidas y prueba cruzada con atlas); a confirmar con el docente (consultas 5 y 6) · **Componente:** cronos-turnos · **Contexto:** Isla 1, issue #33 de atlas-catalogo · **Relacionado:** [ADR 0002](0002-stack.md), [ADR 0004](0004-autenticacion-entre-servicios.md) y [seguridad de atlas-catalogo](../seguridad-atlas-catalogo.md)

## Contexto

El enunciado deja el uso de JHipster como opcional: es "recomendado por la cátedra", pero usarlo o no "no modifica los requisitos funcionales, de integración, seguridad, separación de datos, pruebas y documentación" (3.1). Lo que sí exige, si no se usa, es que el modelo y el contrato de usuarios sean **compatibles con el usuario que genera JHipster**: quien no lo utiliza debe implementar "los mismos datos y comportamientos observables" (3.2).

Cronos-turnos es quien registra usuarios, autentica y emite el JWT ([ADR 0004](0004-autenticacion-entre-servicios.md), decisión del 2026-11-01). Hasta ahora la pregunta de JHipster estaba abierta, con un spike propuesto (generar un proyecto descartable y medir RS256, registro activo y migraciones), y estaba señalada como "se resolverá en un ADR propio" en el ADR 0004.

Estado de cronos al decidir: existe el esqueleto mergeado (PR #6, `dev` en `2f578c6`) con Gradle, Spring Boot 4.1.1, Java 25, Flyway sin migraciones, ArchUnit y el paquete `ar.edu.um.cronos`; es decir, el mismo stack que atlas.

## Opciones evaluadas

| Opción | Pros | Contras |
|---|---|---|
| **A. Spring Security a mano** | Un solo estilo en los dos servicios, un solo migrador (Flyway) y todo el código es propio y explicable. RS256 y registro activo se escriben directamente, sin retoques. Se apoya en el esqueleto ya mergeado. | Hay que escribir la entidad de usuario, el registro, las validaciones, el hash de contraseña, el login y la emisión del token, y sus pruebas. |
| **B. JHipster completo** | Modelo de usuario, registro, BCrypt y validaciones vienen resueltos. La cátedra lo recomienda. | Su JWT es simétrico por defecto y su registro deja al usuario inactivo: obligan a modificar justo las dos partes que ya traía hechas. Los tests generados asumen el secreto. Hay que defender código generado. Trae Liquibase (dos migradores distintos entre servicios) y habría que rehacer el esqueleto ya mergeado. |
| **C. Término medio** | Se genera un proyecto descartable de JHipster y se porta solo el módulo de usuario a un cronos sin JHipster. | Cuesta lo mismo que el spike y, al final, hay que escribir igual RS256, registro activo y pruebas. Se justifica solo si el tiempo de escritura propia resulta excesivo. |

## Decisión

**Opción A: usuarios, registro, login y emisión del JWT con Spring Security, sin JHipster, sobre el esqueleto de cronos que ya está en `dev`.**

Argumentos:

- **El ahorro de JHipster es menor de lo que parece.** Pasar a RS256 (ADR 0004) y dejar al usuario activo al registrarse (enunciado 3.2) obligan a tocar las dos partes que JHipster traía resueltas. Lo que quedaría sin tocar es la entidad, BCrypt y algunas validaciones.
- **El esqueleto ya existe con el stack de atlas.** Partir de JHipster implicaría reemplazarlo o portarlo.
- **Un solo migrador.** Con Flyway en los dos servicios se cierra el "contra" que el ADR 0002 dejó anotado (Liquibase en cronos si se usaba JHipster).
- **Todo el código es defendible.** No hay una parte generada que explicar; en la defensa el README solo necesita decir que no se usó JHipster y por qué.
- **El enunciado lo permite sin costo en requisitos**, siempre que el contrato de usuario sea compatible (ver más abajo).

**Qué no se midió.** No se hizo el spike, así que este ADR **no afirma** que JHipster no pueda cumplir RS256 o el registro activo. Dice que, aun suponiendo que pudiera, el retoque obligado le quita el valor que tendría y suma código generado y un segundo migrador. Los comportamientos por defecto de JHipster 9.3 (firma simétrica, registro inactivo, Liquibase) provienen de las notas del proyecto y del ADR 0004 y siguen sin verificarse con un proyecto generado.

## Contrato de usuario que se implementa

Compatible con el de JHipster, según el enunciado 3.2:

| Aspecto | Qué se implementa |
|---|---|
| Datos del registro | `login`, `password`, `firstName`, `lastName`, `email`, `imageUrl` (opcional) y `langKey`. |
| Datos que decide el backend | Identificador interno, estado de activación, autoridades y campos de auditoría. Quien se registra no puede elegirlos. |
| Activación | El usuario queda **activo** apenas se registra y puede iniciar sesión sin verificar el correo. |
| Contraseña | Se guarda con hash (BCrypt de Spring Security), nunca en texto plano. |
| Token | JWT firmado con **RS256** (clave privada solo en cronos), con `sub` (el usuario) y `auth` (autoridades separadas por espacio, p. ej. `ROLE_USER`), que es lo que atlas ya valida. |
| Rutas | `POST /api/register` y `POST /api/authenticate`, que devuelve `id_token` (la misma forma que el login de la cátedra, 5.2). Implementadas; falta contrastarlas con lo que consuma la app KMP. Ver el [contrato](../../contratos/cronos-turnos-api.md). |
| Recuperación de contraseña | Opcional según el enunciado; fuera del alcance inicial. |

**Validaciones pendientes de ubicar.** El enunciado pide respetar "las validaciones definidas por la cátedra" para el registro del usuario final. Como referencia, el registro de la cuenta técnica de la cátedra usa: `login` de 3 a 50 caracteres, `password` de 4 a 100, `firstName` y `lastName` hasta 50, `email` válido de 5 a 254 y único si se informa, `langKey` de 2 a 10 con `es` por defecto (`INTEGRATION_REFERENCE-v2`, 5.1). Falta confirmar que aplican igual al usuario final de cronos y qué caracteres admite el `login`.

## Consecuencias

- **Hay que escribir y probar** la entidad de usuario con su migración Flyway, el registro con validaciones, el login, la emisión del token y la seguridad de las rutas de cronos. Las pruebas de registro y autenticación del punto 10.1 del enunciado son propias; ninguna se hereda de un generador.
- **Cronos y atlas quedan con el mismo estilo** (Spring Boot, Gradle, Flyway, ArchUnit, hexagonal liviana), lo que simplifica la defensa.
- **Se cierra el issue #33 de atlas** cuando cronos emita un token real y atlas lo valide con los claims `sub` y `auth`; hasta entonces se prueba con `scripts/dev-token.sh`.
- **Las consultas 5 y 6 al docente siguen abiertas** (si se espera JHipster en ambos servicios y si los tests generados cuentan como propios). Esta decisión las vuelve menos urgentes, pero no las responde.
- **Contraseñas largas:** BCrypt no admite más de 72 bytes y el contrato permite 100 caracteres, así que la contraseña se reduce con SHA-256 antes de BCrypt (se encontró al implementar; ver [la implementación](../../implementacion/cronos-turnos.md)).
- **La clave privada de cronos** es un secreto nuevo: se carga por variable o archivo fuera del repo, igual que el resto ([ADR 0001](0001-configuracion-y-secretos.md)).

## Cuándo revisar

- Si el docente pide o exige JHipster en cronos: se reabre y se hace el spike (opción B o C) antes de rehacer nada.
- Si el registro y el login con RS256 no están andando con tiempo suficiente antes de la entrega: se evalúa la opción C para portar el módulo de usuario.
- Si cambia el contrato de usuario de la cátedra: se ajusta la tabla de arriba.

## Referencias

Enunciado 3.1, 3.2 y 10.1; [ADR 0002](0002-stack.md) (D3 y D12); [ADR 0004](0004-autenticacion-entre-servicios.md); consultas 1, 5, 6 y 7 al docente; `INTEGRATION_REFERENCE-v2` (5.1).
