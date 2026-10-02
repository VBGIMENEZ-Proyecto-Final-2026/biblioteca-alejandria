# Isla 0 · Ítaca

**Objetivo:** dejar el entorno y la integración con la cátedra funcionando, para que arrancar `atlas-catalogo` no dependa de nada externo.

**Alcance:** acceso a la red de la cátedra, cuenta técnica, manejo de secretos, los 4 repos y la base de infraestructura con Docker Compose.

**Fuera de alcance:** código de negocio (sync, auth, reservas, UI) y esqueletos de Spring Boot.

**Definición de terminado:**
- Cuenta técnica y JWT guardados fuera de todo repo.
- Conexión verificada a REST, Redis y Kafka de la cátedra.
- Los 4 repos creados, con plantillas y README mínimo.
- `docker compose up` levanta las bases de datos.
- Ningún repo contiene secretos ni IPs (revisar también el historial).

## Issues

### 1. [infra] Conectividad con el servidor de la cátedra (ZeroTier)
Unir la máquina de desarrollo a la red ZeroTier de la cátedra y enviar al administrador el Node ID y la MAC para que autorice el acceso. Sin esto no se puede registrar la cuenta técnica.
- [ ] La máquina de desarrollo aparece autorizada en la red.
- [ ] Hay respuesta de red hacia el servidor (REST, Redis y Kafka alcanzables a nivel de puerto).
- [ ] Los datos de conexión quedan anotados fuera del repo.
Bloquea: 2.

### 2. [infra] Alta de la cuenta técnica del proyecto
Registrar la cuenta con `POST /api/student/register` desde Postman, una única vez. Guardar `id_token` e `integration` en un lugar seguro. Elegir el `groupId` con cuidado: se normaliza, es único y de él salen los nombres de topics y consumer group. Si el token se expone hay que crear otra cuenta y reconfigurar todo.
- [ ] `provisioningStatus` es `PROVISIONED`.
- [ ] `id_token` e `integration` guardados fuera del repo.
- [ ] La colección de Postman usa variables de entorno y no se exporta ni se sincroniza con tokens adentro.
- [ ] `GET /api/student/integration` devuelve la misma configuración.
Depende de: 1. Bloquea: 3 y 6.

### 3. [seguridad] Externalizar secretos y configuración de integración
Definir cómo viajan al código los valores sensibles (JWT técnico, credenciales de Redis, bootstrap de Kafka, URL base de la cátedra). Convención: `.env` ignorado por git, `.env.example` versionado con placeholders, lectura por variables de entorno en Spring.
- [ ] `.gitignore` cubre `.env` y archivos de credenciales.
- [ ] `.env.example` en cada repo, con nombres de variables y sin valores reales.
- [ ] Los dos backends usan el mismo set de variables para la cuenta técnica.
- [ ] Búsqueda en el árbol y en el historial de git sin IPs, tokens ni passwords.
Depende de: 2.

### 4. [infra] Crear los 4 repositorios con estructura base
Crear `hermes-app`, `atlas-catalogo`, `cronos-turnos` y `alejandria-docs`, compartidos con el profe. Cada uno lleva README de arranque, `.gitignore`, `.github/` con issue forms y PR template, y labels cargados con el script.
- [ ] Los 4 repos existen y el profe tiene acceso.
- [ ] Plantillas y labels aplicados en los 4.
- [ ] El README de cada repo enlaza a `alejandria-docs`.
- [ ] Primer commit con mensaje claro (el historial es evidencia).

### 5. [infra] Bases de datos y Docker Compose base
Levantar con Compose las bases de `atlas` y `cronos`. Si comparten instancia física: bases lógicas separadas, usuarios sin permisos cruzados y migraciones independientes. Motor a decidir (PostgreSQL es el candidato natural).
- [ ] `docker compose up` levanta las bases.
- [ ] El usuario de `atlas` no puede conectarse a la base de `cronos`, y viceversa (probado).
- [ ] Credenciales de las bases por variables de entorno.
- [ ] No hay H2, SQLite ni bases embebidas.
Depende de: 3 y 4.

### 6. [infra] Verificar acceso a REST, Redis y Kafka con la cuenta técnica
Smoke test de integración, solo lectura. Es la salida de la isla y el ensayo previo a la Isla 1.
- [ ] `GET /api/synchronization/snapshot` responde 200.
- [ ] Con `redis-cli` y las credenciales de `integration` se leen `catedra:sync:current-version` y `catedra:sync:oldest-available-version`.
- [ ] Se conecta a Kafka y se ve el topic `catedra.catalog.<groupId>`.
- [ ] Resultados documentados en `evidencias/`, sin secretos.
Depende de: 2 y 3.

## Decisiones pendientes (llevar al profe con el formulario "Consulta al profe")
1. **Compose entre repos:** ¿se espera un único `docker compose up` que levante ambos backends, o alcanza con uno por repo (con una red Docker externa compartida)? Afecta los pasos reproducibles del README.
2. **JHipster sí/no:** decidir antes de la Isla 1; cambia cómo se generan los esqueletos.
3. **JWT entre servicios:** propagado del usuario vs. técnico propio (bloquea el diseño de seguridad de ambos backends).
