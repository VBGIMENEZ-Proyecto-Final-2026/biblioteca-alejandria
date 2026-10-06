# Isla 1 · Eolia

**Objetivo:** dejar `atlas-catalogo` funcionando en una versión básica y por separado: mantiene la réplica local del catálogo de la cátedra (snapshot e incremental) y la expone con búsqueda y filtros sobre datos locales.

**Alcance:** todo lo propio de `atlas-catalogo`: decisiones de diseño, esqueleto, persistencia, integración con la cátedra, sincronización, búsqueda, seguridad básica, pruebas, documentación y evidencias.

**Fuera de alcance:** comunicación y contrato entre `atlas-catalogo` y `cronos-turnos`, registro y login de usuarios finales, turnos y reservas, y `hermes-app`.

**Estado del backlog:** por ahora solo están definidos los issues de decisiones de diseño (1 a 3). El resto de las tareas de la isla se agrega cuando sus decisiones estén justificadas.

Formato de cada issue: Componente `atlas`, descripción, criterios, referencias y dependencias (igual que `isla-0-itaca.md`). Las decisiones viven en este repo; los issues solo describen la tarea.

## Issues

### 1. [atlas] Definir el stack tecnológico de atlas-catalogo
Decidir y documentar el stack del servicio (lenguaje, framework, build, base de datos, migraciones, clientes de integración, seguridad y testing), con alternativas, pros y contras de cada decisión.
- [ ] ADR 0002 publicado en `alejandria-docs`.
- [ ] Herramienta de build definida (Maven o Gradle).
- [ ] Algoritmo de firma del JWT definido, o marcado como pendiente de consulta.
- [ ] Decisiones propuestas revisadas y su estado actualizado en el ADR.
Referencias: `arquitectura/adr/0002-stack.md`; enunciado 3, 3.1, 9 y 10.1.
Bloquea: 2, 3 y el esqueleto del proyecto (issue por abrir).

### 2. [atlas] Definir la arquitectura interna de atlas-catalogo
Acordar la arquitectura del servicio: opciones evaluadas, reglas de dependencia, estructura de paquetes y lógica de reconciliación del catálogo.
- [ ] ADR 0003 publicado en `alejandria-docs`.
- [ ] Reglas de dependencia acordadas.
- [ ] Algoritmo de reconciliación revisado, casos borde incluidos.
- [ ] Regla de ArchUnit definida para el primer ticket de código.
Referencias: `arquitectura/adr/0003-arquitectura.md`; enunciado 4.1 y 6.
Depende de: 1. Bloquea: 3 y el esqueleto del proyecto (issue por abrir).

### 3. [atlas] Diseñar el modelo de datos inicial de atlas-catalogo
Definir el boceto del modelo de datos: tablas del catálogo, tablas de control del sync, claves, índices y decisiones abiertas.
- [ ] Documento de modelo de datos publicado en `alejandria-docs`.
- [ ] Decisiones abiertas cerradas o diferidas explícitamente.
- [ ] Alcance de "disponibilidad" definido, o diferido explícitamente.
Referencias: `modelo-datos/atlas-catalogo.md`; enunciado 4.1, 6 y 7.
Depende de: 1 (PostgreSQL, Flyway) y 2.
