# Evidencia · atlas-catalogo en contenedores y con HTTPS

**Fecha:** 2026-11-02 · **Rama:** `feature/dockerfile-compose` de `atlas-catalogo` · **Resultado:** correcto.

Verifica dos cosas que pide el enunciado: la infraestructura se levanta con Docker Compose (sección 3) y el canal puede cifrarse (sección 9). Sin secretos, IPs ni tokens.

## 1. La aplicación en contenedores

```bash
export ATLAS_JWT_PUBLIC_KEY_LOCATION=~/.atlas-dev/dev-public.pem   # clave pública de desarrollo
docker compose --profile app up -d --build
```

| Comprobación | Resultado |
|---|---|
| Build de la imagen (dos etapas, JDK 25 y JRE 25) | Correcto, unos 3 minutos la primera vez |
| `docker compose ps` | `atlas-db` y `atlas-app` en `healthy` (la aplicación tarda unos 20 s en arrancar) |
| Usuario del proceso | `uid=999(atlas)`: no es root |
| `GET /actuator/health` | `200`, `{"status":"UP"}` |
| `GET /api/categories` sin token | `401 NO_AUTENTICADO` |
| `GET /api/categories` con token `ROLE_USER` | `200`, 8 categorías |
| `GET /api/sync/status` con `ROLE_USER` | `403 SIN_PERMISO` |
| `GET /api/sync/status` con `ROLE_ADMIN` | `200`, `localVersion: 1`, `status: IDLE`, `lastResult: NOOP`, sin error |
| `GET /api/professionals?size=2` | `200`, `totalElements: 24` |
| Contenido de la base | 24 profesionales, 8 categorías, 44 horarios |
| Token vencido | `401 NO_AUTENTICADO` |
| `POST /api/professionals` y ruta inexistente | `403 SIN_PERMISO` |

### Lo que se vio al arrancar

- **La sincronización de arranque falló la primera vez** (`CATEDRA_NO_DISPONIBLE`: Redis no respondió) y la aplicación **siguió arrancada**, como está diseñado. Los primeros intentos del consumidor de Kafka también fallaron por conexión y reintentó solo hasta unirse al grupo, unos 40 s después. Al consultar, la copia estaba al día (`localVersion: 1`, `lastResult: NOOP`, sin error). No se registró cuál disparador la dejó así.
- **SELinux:** en Fedora el montaje de la clave pública sin etiqueta dejaba el archivo ilegible para el contenedor (`No existe el archivo de la clave pública JWT`). Se resolvió con `:z` en el volumen del `compose.yaml`.
- **Healthcheck:** la imagen base del JRE no trae `curl`; se instala en la imagen para el healthcheck del compose.

## 2. HTTPS con las variables estándar de Spring Boot

Con un certificado autofirmado de prueba (PKCS12, 2048 bits, 30 días) pasado por `SERVER_SSL_KEY_STORE`, `SERVER_SSL_KEY_STORE_PASSWORD` y `SERVER_SSL_KEY_STORE_TYPE`, en un contenedor aparte con la sincronización apagada:

| Comprobación | Resultado |
|---|---|
| `curl -k https://localhost:8443/actuator/health` | `200`, `UP`, negociado con **TLSv1.3** |
| `curl http://localhost:8443/actuator/health` (HTTP plano al mismo puerto) | `400 Bad Request`: "This combination of host and port requires TLS" |

El almacén y su contraseña no se versionan (`*.p12` y `*.jks` están en `.gitignore`). El contenedor de prueba se eliminó al terminar.

## 3. Límites de esta evidencia

- Se probó con una clave de **desarrollo**, no con tokens emitidos por `cronos-turnos` (que todavía no existe).
- HTTPS está probado a mano, no con un test automatizado; el certificado es autofirmado.
- La red de la cátedra es privada (ZeroTier): desde el contenedor funcionó, pero la primera conexión a Redis falló en el arranque. No se investigó la causa.
