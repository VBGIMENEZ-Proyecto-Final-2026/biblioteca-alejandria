# Isla 1 · Eolia

**Objetivo:** dejar `atlas-catalogo` funcionando en una versión básica y por separado: mantiene la réplica local del catálogo de la cátedra (snapshot e incremental) y la expone con búsqueda y filtros sobre datos locales.

**Alcance:** todo lo propio de `atlas-catalogo`: decisiones de diseño, esqueleto, persistencia, integración con la cátedra, sincronización, búsqueda, seguridad básica, pruebas, documentación y evidencias.

**Fuera de alcance:** comunicación y contrato entre `atlas-catalogo` y `cronos-turnos`, registro y login de usuarios finales, turnos y reservas, y `hermes-app`.

**Estado del backlog:** los issues de decisiones de diseño (1 a 3) y el esqueleto del proyecto (4) están hechos (issues #5, #6, #7 y #9 de `atlas-catalogo`). Están en curso migraciones y persistencia (6), abierto, y el cliente REST de la cátedra (7), con el borrador listo y el issue por abrir. El resto de las tareas de la isla se agrega cuando sus decisiones estén justificadas. La numeración es la del backlog completo, por eso el 5 (seguridad base) todavía no aparece.

Formato de cada issue: Componente `atlas`, descripción, criterios, referencias y dependencias (igual que `isla-0-itaca.md`). Las decisiones viven en este repo; los issues solo describen la tarea.

## Issues

### 1. [atlas] Definir el stack tecnológico de atlas-catalogo
Decidir y documentar el stack del servicio (lenguaje, framework, build, base de datos, migraciones, clientes de integración, seguridad y testing), con alternativas, pros y contras de cada decisión.
- [x] ADR 0002 publicado en `alejandria-docs`.
- [x] Herramienta de build definida (Maven o Gradle).
- [x] Algoritmo de firma del JWT definido, o marcado como pendiente de consulta.
- [x] Decisiones propuestas revisadas y su estado actualizado en el ADR.
Estado: hecho (issue #5 de `atlas-catalogo`), publicado en `arquitectura/adr/0002-stack.md`.
Referencias: `arquitectura/adr/0002-stack.md`; enunciado 3, 3.1, 9 y 10.1.
Bloquea: 2, 3 y 4.

### 2. [atlas] Definir la arquitectura interna de atlas-catalogo
Acordar la arquitectura del servicio: opciones evaluadas, reglas de dependencia, estructura de paquetes y lógica de reconciliación del catálogo.
- [x] ADR 0003 publicado en `alejandria-docs`.
- [x] Reglas de dependencia acordadas.
- [x] Algoritmo de reconciliación revisado, casos borde incluidos.
- [x] Regla de ArchUnit definida para el primer ticket de código.
Estado: hecho (issue #6 de `atlas-catalogo`), publicado en `arquitectura/adr/0003-arquitectura.md`.
Referencias: `arquitectura/adr/0003-arquitectura.md`; enunciado 4.1 y 6.
Depende de: 1. Bloquea: 3 y 4.

### 3. [atlas] Diseñar el modelo de datos inicial de atlas-catalogo
Definir el boceto del modelo de datos: tablas del catálogo, tablas de control del sync, claves, índices y decisiones abiertas.
- [x] Documento de modelo de datos publicado en `alejandria-docs`.
- [x] Decisiones abiertas cerradas o diferidas explícitamente.
- [x] Alcance de "disponibilidad" definido, o diferido explícitamente.
Estado: hecho (issue #7 de `atlas-catalogo`), publicado en `modelo-datos/atlas-catalogo.md`.
Referencias: `modelo-datos/atlas-catalogo.md`; enunciado 4.1, 6 y 7.
Depende de: 1 (PostgreSQL, Flyway) y 2. Bloquea: 4 y 6.

### 4. [atlas] Esqueleto del proyecto atlas-catalogo
Crear el proyecto Spring Boot con el stack y la estructura de paquetes decididos en los ADR 0002 y 0003: que compile, arranque, se conecte a la PostgreSQL del compose con Flyway configurado y responda su endpoint de salud. Sin tablas, sin lógica de sincronización y sin seguridad.
- [x] Spring Boot 4.1, Java 25 y Gradle (Kotlin DSL), con wrapper 9.1.0 o superior.
- [x] Dependencias mínimas (Web, Actuator, Data JPA, Flyway, PostgreSQL y las de test, con ArchUnit 1.4.1 o superior); Kafka, Redis y Security en sus propios issues.
- [x] Estructura de paquetes del ADR 0003.
- [x] Conexión a la base solo por variables de entorno (`ATLAS_DB_*`); las `CATEDRA_*` las declara cada issue de cliente.
- [x] Flyway configurado; la aplicación arranca sin migraciones.
- [x] `/actuator/health` responde y es el único endpoint de Actuator expuesto.
- [x] Test de contexto con Testcontainers sobre Java 25 (si falla el tooling, se documenta y se evalúa Java 21).
- [x] Las tres reglas de ArchUnit del ADR 0003 activas y pasando con paquetes vacíos.
- [x] `./gradlew build` pasa.
- [x] README con requisitos, cómo levantar la base, correr la aplicación y ejecutar los tests.
Estado: hecho (issue #9 y PR #10 de `atlas-catalogo`). El paquete base es `ar.edu.um.atlas` (ADR 0003).
Referencias: ADR 0001, 0002 y 0003; `modelo-datos/atlas-catalogo.md` (decisión L); enunciado 3 y 3.1.
Depende de: 1, 2 y 3 (hechos) y de Isla 0. Bloquea: 6, seguridad base, cliente REST y cliente Redis (estos tres, por abrir).

### 6. [atlas] Migraciones y persistencia del catálogo
Crear con Flyway el esquema del modelo de datos (categorías, profesionales, horarios semanales y la fila de control del sync) y las entidades JPA y repositorios que lo usan, con tests de persistencia contra PostgreSQL real. Solo guarda y lee: sin lógica de sincronización.
- [ ] Migración `V1` que crea desde una base vacía las cuatro tablas con sus tipos, claves, claves foráneas e índices, y la fila inicial de `sync_state`.
- [ ] Solo las restricciones del modelo (`NOT NULL`, claves foráneas, dominio de `day_of_week` y `id = 1` en `sync_state`).
- [ ] Entidades JPA en `domain` (sin Spring) y repositorios de Spring Data en `application.repository`.
- [ ] *Upsert* idempotente por ID en los repositorios del catálogo y lectura de `sync_state` con candado (`SELECT ... FOR UPDATE`).
- [ ] Hibernate valida las entidades contra el esquema.
- [ ] Tests de persistencia contra PostgreSQL real con Testcontainers (no H2).
- [ ] Reglas de ArchUnit de `domain` y `application` activas sin `allowEmptyShould(true)`.
- [ ] `./gradlew build` pasa y el README está actualizado.
Estado: abierto (issue #11 de `atlas-catalogo`).
Referencias: `modelo-datos/atlas-catalogo.md`; ADR 0002 (D5 a D7 y D13) y ADR 0003; enunciado 3 y 4.1.
Depende de: 3 y 4 (hechos). Bloquea: sincronización completa, sincronización incremental, búsqueda y estado (issues por abrir).

### 7. [atlas] Cliente REST de la cátedra: snapshot del catálogo
Pedir a la cátedra el snapshot completo con el JWT técnico, con timeouts definidos, reintentos acotados y errores traducidos. No incluye login: el `id_token` ya es el JWT técnico de un año (referencia de integración 4 y ADR 0001) y renovarlo con `/api/authenticate` exigiría usuario y contraseña que no forman parte de las variables `CATEDRA_*`.
- [ ] Puerto `CatalogSnapshotSource` con modelo propio y adaptador `RestClient` declarativo en `adapters.out.rest`.
- [ ] `CATEDRA_REST_BASE_URL` y `CATEDRA_ID_TOKEN` declaradas y validadas al arrancar.
- [ ] Interpreta instantes UTC, horas `HH:mm` y `HH:mm:ss` y campos desconocidos.
- [ ] Timeouts configurables y reintentos acotados solo ante fallas transitorias.
- [ ] Errores traducidos por `status` y `code`; el token nunca se escribe en logs.
- [ ] Tests con respuestas simuladas, incluyendo errores, y una verificación manual contra la cátedra real.
Estado: borrador listo, issue por abrir.
Referencias: `catedra/INTEGRATION_REFERENCE-v2.md` (4, 6, 7, 13 y 18.4); ADR 0001, 0002 (D10 y D11) y 0003; enunciado 4.1, 6 y 9.
Depende de: 4 (hecho). No depende del 6. Bloquea: sincronización completa (issue por abrir).
