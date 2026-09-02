# Manual de Monitoreo del Servicio

> Estado: **diseño de referencia, aún no implementado.** Este documento responde "¿tenemos monitoreo hoy?" (no) y describe qué agregar, con contenido de código/compose literal y listo para copiar cuando decidan construirlo. Nada de lo descrito aquí existe todavía en los repositorios.

## 1. Estado actual

Hoy no existe ningún tipo de monitoreo. Concretamente, verificado directamente contra el código:

- **`/api/health/`** (`backend/config/urls.py:25`) es una función lambda vacía en línea:
  ```python
  path("api/health/", lambda request: JsonResponse({"status": "ok"}), name="health"),
  ```
  No verifica nada. Devuelve `200 {"status": "ok"}` mientras el *proceso* de Django/gunicorn esté vivo y enrutando solicitudes — incluso si Postgres o Redis están completamente caídos. Hoy existe únicamente como una verificación manual, de una sola vez, de "¿funcionó el despliegue?" en los manuales de despliegue, no como un objetivo de vigilancia continua.
- **El `HEALTHCHECK` de Docker** solo existe en `db` y `cache` (`infra/docker-compose.yml` — `pg_isready` / `redis-cli ping`, cada 5s). `backend`, `frontend` y `communications_worker` **no** tienen ninguna directiva de healthcheck; `depends_on: condition: service_healthy` solo condiciona el arranque a que `db`/`cache` estén listos, nada observa si `backend` en sí realmente está sirviendo solicitudes.
- **No hay un flujo de registros (logging) centralizado.** No existe ningún diccionario `LOGGING` en `backend/config/settings/{base,dev,prod,test}.py` — Django recurre a su comportamiento por defecto (registro a stderr). No hay manejador de archivo/archivo rotativo, nada se envía fuera del servidor.
- **No hay herramientas de métricas/APM.** Confirmado por búsqueda: no hay Sentry, Prometheus, Grafana, Datadog, New Relic, Elastic, Loki, statsd, ni OpenTelemetry en ninguno de los tres repositorios.
- **`AuditLog`** (`apps/core/models.py`) existe, pero es una **bitácora de cumplimiento/seguridad** de acciones de usuarios (quién leyó/editó/eliminó qué registro) — no es una señal de salud del sistema. No confundir ambas cosas.
- **La única recuperación automática que existe** es `restart: unless-stopped` en cada servicio. Esto es completamente pasivo: si el bucle de `communications_worker` empieza a fallar silenciosamente en cada ciclo, o un contenedor entra en un bucle de reinicio, nada le avisa a una persona — los contenedores simplemente se siguen reiniciando indefinidamente.

Ningún documento existente (`architecture.md`, `deployment-guide.md`, `PROGRESS.md`) había señalado esto antes como una brecha registrada — este es el primer lugar donde queda por escrito.

## 2. Dos correcciones previas necesarias

Ambas son cambios de código/configuración pequeños y puntuales. Aplíquelas *antes* de apuntar un panel de monitoreo al stack — de lo contrario, el panel reportará todo en verde durante una interrupción real, lo cual es peor que no tener panel.

### 2a. Hacer que `/api/health/` verifique realmente sus dependencias

Muévalo de `urls.py` a una vista real en `apps/core/`, ej. `apps/core/views.py`:

```python
from django.core.cache import cache
from django.db import connections
from django.db.utils import OperationalError
from django.http import JsonResponse


def health_check(request):
    checks = {}

    try:
        with connections["default"].cursor() as cursor:
            cursor.execute("SELECT 1")
        checks["database"] = "ok"
    except OperationalError:
        checks["database"] = "error"

    try:
        cache.set("health_check_probe", "1", timeout=5)
        checks["cache"] = "ok" if cache.get("health_check_probe") == "1" else "error"
    except Exception:
        checks["cache"] = "error"

    healthy = all(v == "ok" for v in checks.values())
    return JsonResponse({"status": "ok" if healthy else "error", "checks": checks}, status=200 if healthy else 503)
```

(Usa `CACHES["default"]` — el `django.core.cache.backends.redis.RedisCache` de este proyecto, `backend/config/settings/base.py:141` — mediante la API de caché propia de Django, en vez de una librería cliente de Redis, ya que este proyecto no depende de ninguna.)

Y en `backend/config/urls.py`, reemplace la lambda:

```python
from apps.core.views import health_check
...
path("api/health/", health_check, name="health"),
```

Esto es lo que hace que tanto la verificación posterior al despliegue del pipeline ([`manual-pipeline-cicd.md`](manual-pipeline-cicd.md) §5/§10) como el monitor del panel de abajo signifiquen algo real.

### 2b. Agregar healthchecks de Docker a los tres servicios restantes

En `infra/docker-compose.prod.yml`, siguiendo el mismo patrón ya usado en `db`/`cache`:

```yaml
  backend:
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/api/health/"]
      interval: 15s
      timeout: 5s
      retries: 5

  communications_worker:
    healthcheck:
      test: ["CMD-SHELL", "test -f /tmp/comms_worker_alive"]
      interval: 90s
      timeout: 5s
      retries: 3
```

`communications_worker` no tiene un servidor HTTP que consultar — su propio comando de compose (`infra/docker-compose.yml`) es un bucle `sh -c "while true; do ...; sleep 60; done"`. Agregue un `touch /tmp/comms_worker_alive` al inicio de cada iteración del bucle para que el healthcheck tenga algo que revisar; sin esta línea adicional en el comando del bucle, un healthcheck de Docker no puede distinguir entre "colgado" y "corriendo".

`frontend` (nginx) no lo necesita estrictamente para funcionar — si nginx muere, se cae todo el contenedor de todos modos, lo cual Docker ya reporta como `Exited` — pero agregar uno trivial mantiene uniforme la verificación de "todos los contenedores reportan healthy" del pipeline de CD:

```yaml
  frontend:
    healthcheck:
      test: ["CMD", "wget", "--no-check-certificate", "-qO-", "https://localhost/"]
      interval: 15s
      timeout: 5s
      retries: 5
```

## 3. Uptime Kuma como nuevo servicio de compose

[Uptime Kuma](https://github.com/louislam/uptime-kuma) es un solo contenedor autoalojado: un panel de estado con monitores de disponibilidad integrados, gráficos de tiempo de respuesta e integraciones de notificación, que guarda su propio estado en SQLite. Encaja bien en este despliegue — un contenedor más, ligero, sin dependencia externa, sin una base de datos separada que administrar, y una interfaz que un desarrollador sin experiencia en DevOps puede operar sin aprender un lenguaje de consultas (la alternativa, Prometheus + Grafana, es más potente pero es en sí misma una pequeña plataforma de métricas — varios contenedores, ajuste propio de almacenamiento/retención, y una curva de aprendizaje más pronunciada para un despliegue de un solo servidor donde el requisito real es "¿está funcionando, y se le avisó a alguien cuando no lo estuvo?").

Agregue a `infra/docker-compose.prod.yml`:

```yaml
  monitor:
    image: louislam/uptime-kuma:1
    container_name: mc_prod_monitor
    restart: unless-stopped
    volumes:
      - kuma_data:/app/data
    ports:
      - "127.0.0.1:3001:3001"   # solo loopback — vea la sección 4 sobre acceso remoto

volumes:
  kuma_data:
```

> **No** publique este puerto de forma más amplia (ej. `"3001:3001"`, o la IP de la LAN del servidor) sin decidirlo deliberadamente — enlazarlo a `127.0.0.1` como arriba significa que solo es alcanzable desde el propio servidor. La sección 4 abajo explica cómo llegar realmente a él, que deliberadamente no es "abrirlo en la LAN".
>
> Si sí quiere que sea alcanzable desde otras máquinas en la LAN de la clínica directamente (no solo por VPN), enlácelo a la IP de la LAN del servidor en vez de `127.0.0.1` — pero nunca a `0.0.0.0`/todas las interfaces, por la misma razón que la aplicación misma nunca se expone así.

Configuración inicial, una vez que el contenedor esté arriba:

1. Desde el servidor, abra `http://localhost:3001` y complete el asistente de configuración (cree la cuenta de administrador — trate estas credenciales con la misma seriedad que cualquier otra cuenta de administrador aquí).
2. Agregue un **monitor HTTP(s)** por cada cosa que valga la pena vigilar:
   - `https://localhost/api/health/` (o la propia IP del servidor) — este es el más importante una vez aplicada la sección 2a, ya que refleja la salud de DB+Redis, no solo "gunicorn está arriba".
   - `https://localhost/` — confirma que el frontend/nginx realmente está sirviendo páginas, no solo que el contenedor existe.
   - Opcionalmente, un **monitor de contenedor Docker** (Kuma lo soporta mediante el socket de Docker) para cada uno de los cinco contenedores de la aplicación, para que un contenedor en bucle de reinicio aparezca aunque su superficie HTTP siga respondiendo por casualidad.
3. Agregue una **notificación** (Settings → Notifications → Setup Notification): elija **SMTP/Email**, y reutilice el buzón de correo *ya existente* configurado para el módulo de Comunicaciones (`EMAIL_HOST` / `EMAIL_PORT` / `EMAIL_HOST_USER` / `EMAIL_HOST_PASSWORD` / `EMAIL_USE_TLS` en `.env`) en vez de dar de alta un segundo buzón — no se necesita ningún secreto nuevo. Asocie esa notificación a cada monitor.

## 4. Acceso remoto

**Sí, puede acceder remotamente — a través de la VPN, no abriendo el puerto del panel a internet, y tampoco principalmente conectándose por escritorio remoto al servidor.**

El panel está enlazado únicamente a la interfaz loopback/LAN del servidor (sección 3), a propósito — exactamente la misma regla de "nunca exponer esta máquina a internet público" que el manual de despliegue ya aplica a la aplicación misma (`manual-despliegue.md` Capítulo 9 / el capítulo de red de `deployment-guide.md`: sin reenvío de puertos, UPnP/DMZ deshabilitados). La forma recomendada de acceder desde fuera de la clínica es la **misma VPN ya documentada ahí** para acceso remoto legítimo (ej. WireGuard): una vez que su laptop esté conectada a esa VPN, se comporta como si estuviera físicamente en la LAN de la clínica, y navega directamente a `http://<ip-lan-del-servidor>:3001` (si lo enlazó a la IP de la LAN en vez de loopback) exactamente igual que accede a la aplicación misma en `https://<ip-lan-del-servidor>`.

Por qué la VPN y no una sesión de RDP/escritorio remoto al servidor, como método principal:

- **Una sola inversión, todo cubierto.** La VPN ya le da acceso a la aplicación, al panel, y (si alguna vez se necesita) también a una sesión RDP/SSH — es estrictamente más capaz, no una alternativa excluyente.
- **RDP es en sí mismo un puerto comúnmente atacado** y, como todo lo demás aquí, nunca debe exponerse directamente a internet — así que acceder a él remotamente *también* requiere la VPN (o una ruta igualmente tunelizada) de todas formas. No existe un escenario donde RDP sea alcanzable pero la VPN no también sea necesaria, así que RDP agrega un paso en vez de ahorrar uno.
- **Costo en recursos.** Una sesión completa e interactiva de escritorio remoto (renderizar un escritorio, mantener una sesión de usuario activa) es una carga más pesada sobre hardware que usted ha señalado como posiblemente limitado, solo para ver una página de estado. Un túnel VPN llevando una sola solicitud de navegador es mucho más económico.

Si la VPN realmente no está configurada todavía y necesita revisar el panel *hoy*, una sesión RDP al servidor (solo por la LAN, nunca abierta a internet) y cargar `http://localhost:3001` localmente desde dentro de esa sesión funciona como solución temporal — solo no la trate como el plan a largo plazo; configure la VPN y úsela en su lugar.

## 5. Qué alerta y cómo

Con la configuración de la sección 3, Kuma notificará (por correo, a la o las direcciones que configure en sus ajustes de notificación) cuando:

- Una URL monitoreada deje de devolver un estado exitoso (el sitio está caído, o `/api/health/` empieza a devolver `503` porque falló la verificación de base de datos o de caché).
- El tiempo de respuesta supere el umbral que configure por monitor (útil para detectar "está arriba pero con dificultades" antes de que se convierta en "está caído").
- Un contenedor monitoreado (si agregó monitores de contenedor Docker) se detiene, sale, o entra en un bucle de reinicio.

También ofrece, de forma opcional, una página de estado pública — no relevante aquí ya que esto se mantiene solo en LAN/VPN, pero vale la pena saber que existe por si en el futuro surge la necesidad de un tablero de estado visible para el personal.

## 6. Mantenimiento

Los propios datos de Uptime Kuma en SQLite (volumen `kuma_data`) contienen solo la configuración de monitores y el historial de disponibilidad/tiempos de respuesta — nada de datos de pacientes, nada sensible en términos de PII, nada relevante para cumplimiento. Trátelo como de bajo riesgo y recreable: respáldelo de forma oportunista (un simple `docker run --rm -v medicalconsultations-prod_kuma_data:/data -v <carpeta-de-respaldo>:/backup alpine tar czf /backup/kuma_data.tar.gz /data` periódico es suficiente) en vez de integrarlo al flujo de retención/restauración de `backup_db.ps1`, consciente del PII — mezclar ambos difuminaría lo que realmente necesita el manejo cuidadoso descrito, con las advertencias de `PII_FIELD_KEY`, en `manual-respaldo.md`.

## Vea también

- [`manual-pipeline-cicd.md`](manual-pipeline-cicd.md) — el pipeline de despliegue cuya verificación depende de la corrección de `/api/health/` en la sección 2a de aquí.
- [`manual-despliegue.md`](manual-despliegue.md) / [`deployment-guide.md`](../deployment-guide.md) — el capítulo de red/VPN en el que se apoya la guía de acceso remoto de este documento.
- [`manual-respaldo.md`](manual-respaldo.md) — el proceso de respaldo/restauración consciente del PII del que deben mantenerse separados los datos de bajo riesgo de Kuma.
