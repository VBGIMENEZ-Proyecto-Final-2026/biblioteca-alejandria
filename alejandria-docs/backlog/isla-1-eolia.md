# Isla 1 · Eolia

**Objetivo:** dejar `atlas-catalogo` funcionando en una versión básica y por separado: mantiene la réplica local del catálogo de la cátedra (snapshot e incremental) y la expone con búsqueda y filtros sobre datos locales.

**Alcance:** todo lo propio de `atlas-catalogo`: decisiones de diseño, esqueleto, persistencia, integración con la cátedra, sincronización, búsqueda, seguridad básica, pruebas, documentación y evidencias.

**Fuera de alcance:** comunicación y contrato entre `atlas-catalogo` y `cronos-turnos`, registro y login de usuarios finales, turnos y reservas, y `hermes-app`.

**Estado del backlog:** los issues de decisiones de diseño (1 a 3) están hechos (issues #5, #6 y #7 de `atlas-catalogo`). El resto de las tareas de la isla se agrega cuando sus decisiones estén justificadas; el esqueleto del proyecto (issue 4) es el siguiente y está abierto.

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
Depende de: 1 (PostgreSQL, Flyway) y 2. Bloquea: 4 y el issue de migraciones y persistencia (por abrir).

### 4. [atlas] Esqueleto del proyecto atlas-catalogo
Crear el proyecto Spring Boot con el stack y la estructura de paquetes decididos en los ADR 0002 y 0003: que compile, arranque, se conecte a la PostgreSQL del compose con Flyway configurado y responda su endpoint de salud. Sin tablas, sin lógica de sincronización y sin seguridad.
- [ ] Spring Boot 4.1, Java 25 y Gradle (Kotlin DSL), con wrapper 9.1.0 o superior.
- [ ] Dependencias mínimas (Web, Actuator, Data JPA, Flyway, PostgreSQL y las de test, con ArchUnit 1.4.1 o superior); Kafka, Redis y Security en sus propios issues.
- [ ] Estructura de paquetes del ADR 0003.
- [ ] Conexión a la base solo por variables de entorno (`ATLAS_DB_*`); las `CATEDRA_*` las declara cada issue de cliente.
- [ ] Flyway configurado; la aplicación arranca sin migraciones.
- [ ] `/actuator/health` responde y es el único endpoint de Actuator expuesto.
- [ ] Test de contexto con Testcontainers sobre Java 25 (si falla el tooling, se documenta y se evalúa Java 21).
- [ ] Las tres reglas de ArchUnit del ADR 0003 activas y pasando con paquetes vacíos.
- [ ] `./gradlew build` pasa.
- [ ] README con requisitos, cómo levantar la base, correr la aplicación y ejecutar los tests.
Estado: abierto (issue #9 de `atlas-catalogo`).
Referencias: ADR 0001, 0002 y 0003; `modelo-datos/atlas-catalogo.md` (decisión L); enunciado 3 y 3.1.
Depende de: 1, 2 y 3 (hechos) y de Isla 0. Bloquea: seguridad base, migraciones y persistencia, cliente REST y cliente Redis (issues por abrir).
