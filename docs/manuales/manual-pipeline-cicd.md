# Manual del Pipeline CI/CD

> Estado: **diseño de referencia, aún no implementado.** El CI (pruebas/compilación/validación) ya corre hoy mediante GitHub Actions en los tres repositorios. Este documento diseña la mitad que falta — el CD (despliegue continuo) — para enviar automáticamente un commit fusionado en `main` al servidor de la clínica, sin necesidad de una sesión manual por SSH/RDP, e incluye el contenido literal (workflow y script) listo para copiar y usar cuando decidan construirlo. Nada de lo descrito aquí existe todavía en los repositorios.

## 1. Dónde encaja esto

### Qué hace el CI hoy

Los tres repositorios (`backend`, `frontend`, `infra`) ejecutan un workflow de GitHub Actions en cada push/PR a `dev` y `main` (además de `workflow_dispatch` manual):

| Repositorio | Workflow | Job | Qué hace |
|---|---|---|---|
| `backend` | `.github/workflows/ci.yml` | `test` | `pip install -r requirements/dev.txt` → `python manage.py check --settings config.settings.test` → `pytest` |
| `frontend` | `.github/workflows/ci.yml` | `build` | `npm ci` → `npm test` → `npm run build` (verificación de tipos + build de Vite) |
| `infra` | `.github/workflows/ci.yml` | `compose-config` | `docker compose config --quiet` para el stack de dev y el de prod — solo valida el YAML/la interpolación, nunca construye ni corre un contenedor de verdad |

Ninguno de los tres construye un artefacto desplegable, sube una imagen, ni toca el servidor. `infra/docs/architecture.md` §6 lleva desde la planificación inicial del proyecto un marcador para esto: *"(later) push to registry / deploy to laptop."* Este documento reemplaza ese marcador.

### Qué significa "desplegar una actualización" hoy (proceso manual)

Según `infra/docs/deployment-guide.md` y `infra/docs/manuales/manual-despliegue.md`, hoy una persona:

1. Lleva el código más reciente al servidor como tres carpetas **hermanas** (`backend/`, `frontend/`, `infra/` dentro de una misma carpeta padre) — los contextos `build: ../backend` / `build: ../frontend` de los archivos compose dependen exactamente de esa estructura.
2. Desde `infra/`, ejecuta:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
   ```
   Esto reconstruye las imágenes de `backend`/`frontend` desde el código fuente, y el comando de arranque del contenedor `backend` ejecuta `migrate` + `collectstatic` antes de iniciar `gunicorn` — así que reiniciar `backend` es *cómo* se aplican las migraciones. No hay un paso separado de migración que se pueda olvidar.
3. Verifica con `docker compose ... ps` (todos los contenedores `running`/`healthy`) y una revisión por navegador/`curl` contra `https://<ip-del-servidor>`.

**El pipeline descrito a continuación es una automatización directa de estos tres pasos** — no es un proceso nuevo ni un modelo de despliegue distinto (por ejemplo, no introduce un registro de contenedores; las imágenes se siguen construyendo en el propio servidor, igual que hoy).

## 2. Por qué un runner autoalojado (self-hosted)

Los runners de GitHub en la nube solo pueden alcanzar su servidor mediante una conexión *entrante* — típicamente SSH. Los manuales de despliegue existentes establecen, deliberadamente, que este servidor **no tiene puertos entrantes**: está en una red privada detrás de un módem residencial de Claro/Altice, UPnP y DMZ están deshabilitados, y nada está reenviado (port-forward) (vea el Capítulo 8 de `manual-despliegue.md` / el capítulo de red de `deployment-guide.md`). Abrir SSH hacia internet para dejar entrar a un runner en la nube violaría directamente esa regla, y las conexiones residenciales en RD suelen estar además detrás de CGNAT, por lo que ni siquiera podría garantizarse una ruta entrante estable.

Un **runner autoalojado de GitHub Actions** invierte la dirección: es un pequeño agente instalado *en* el servidor que consulta a GitHub mediante una conexión saliente HTTPS normal, igual que una pestaña de navegador. GitHub le asigna un trabajo en cola; el runner lo recoge y lo ejecuta localmente. Sin puertos entrantes, sin llaves SSH expuestas a internet, sin necesidad de VPN solo para esto — es el patrón estándar para "desplegar a una máquina que no es alcanzable desde internet", que describe exactamente a este servidor.

## 3. Diseño recomendado de disparadores (triggers)

Un runner autoalojado en una cuenta personal de GitHub (no una organización) se registra a **un repositorio específico** — no existe un grupo de runners compartido a nivel de organización en repositorios individuales. Dado que solo `infra` posee los archivos de Docker Compose que realmente ejecutan el despliegue, el diseño es:

- **Un solo runner, registrado en `infra`.** Es el único repositorio que lo necesita.
- **El propio push de `infra` a `main`** dispara un despliegue directamente (un cambio solo en `infra`, ej. un ajuste de compose o de `.env.example`, debe redesplegar).
- **`backend` y `frontend`**, al terminar exitosamente su build en `main`, disparan un evento `repository_dispatch` *hacia* `infra`, que el runner recoge y trata igual que su propio disparador de push.

Esto significa que cualquiera de los tres repositorios que actualice `main` produce exactamente un redespliegue, y toda la lógica de despliegue (secretos, scripts, el runner mismo) vive en un solo lugar en vez de triplicarse. La alternativa — un runner autoalojado por repositorio — se consideró y se descartó: triplica el número de agentes de larga duración en una máquina con recursos limitados sin ningún beneficio funcional, ya que `backend`/`frontend` no tienen nada que desplegar sin los archivos de compose de `infra`.

## 4. Configurar el runner

1. En el repositorio `infra` en GitHub: **Settings → Actions → Runners → New self-hosted runner**. Elija el sistema operativo destino (Windows x64 para Windows 10/11/Server, Linux x64 para un servidor Linux) — GitHub genera un token de registro de un solo uso y los comandos exactos de descarga/configuración para ese sistema operativo.
2. Ejecute el `config.cmd` (Windows) o `config.sh` (Linux) generado en el servidor, asignándole una etiqueta, ej. `clinic-server`, para que el workflow de despliegue pueda apuntarle explícitamente (`runs-on: [self-hosted, clinic-server]`) en vez de a cualquier runner autoalojado que pueda existir más adelante.
3. **Instálelo como servicio**, no como una sesión interactiva — esto es lo que le permite sobrevivir a un reinicio y seguir funcionando sin que nadie tenga la sesión iniciada:
   - **Windows:** `.\svc.cmd install` y luego `.\svc.cmd start` (ejecutar como Administrador una sola vez, dentro de la carpeta de instalación del runner).
   - **Linux:** `sudo ./svc.sh install` y luego `sudo ./svc.sh start`.
4. Use una **cuenta de sistema operativo dedicada, de bajo privilegio**, para correr el servicio, en vez de una cuenta personal de administrador — solo necesita permiso para ejecutar `docker`/`docker compose` y leer/escribir dentro del árbol de carpetas `MedicalConsultations`. En Windows, agregue esa cuenta al grupo `docker-users`; en Linux, al grupo `docker`.
5. Verifique: el nuevo runner debe aparecer como **Idle** bajo Settings → Actions → Runners en GitHub dentro del primer minuto de iniciado el servicio.

## 5. El workflow de despliegue

Cree `infra/.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [main]
  repository_dispatch:
    types: [deploy]

concurrency:
  group: production-deploy
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: [self-hosted, clinic-server]
    steps:
      - name: Checkout infra
        uses: actions/checkout@v4

      - name: Pull latest backend and frontend
        shell: pwsh
        run: |
          git -C ../backend fetch origin main
          git -C ../backend reset --hard origin/main
          git -C ../frontend fetch origin main
          git -C ../frontend reset --hard origin/main

      - name: Backup before deploying
        shell: pwsh
        run: ./scripts/backup_db.ps1

      - name: Build and restart the stack
        run: docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

      - name: Verify containers are healthy
        shell: pwsh
        run: |
          Start-Sleep -Seconds 15
          $bad = docker compose -f docker-compose.yml -f docker-compose.prod.yml ps --format json |
            ConvertFrom-Json | Where-Object { $_.State -ne 'running' -and $_.Health -notin @('healthy', '') }
          if ($bad) { throw "Unhealthy container(s) after deploy: $($bad.Name -join ', ')" }

      - name: Verify the API is actually serving
        shell: pwsh
        run: |
          $resp = Invoke-WebRequest -Uri "https://localhost/api/health/" -SkipCertificateCheck -UseBasicParsing
          if ($resp.StatusCode -ne 200) { throw "Health check returned $($resp.StatusCode)" }
```

Notas sobre las decisiones tomadas aquí:

- **`git -C ../backend reset --hard origin/main`** en vez de un `actions/checkout` anidado para los repos hermanos — la acción checkout de GitHub ancla las rutas dentro del propio directorio de trabajo del job (`_work/infra/infra/...`); llegar a las carpetas hermanas reales de al lado (que es lo que requieren los contextos `build:` de compose) es más simple y transparente con un par de comandos `git` que pelear con el manejo de rutas de la acción.
- **`concurrency: production-deploy`** garantiza que dos despliegues (ej. un merge de `backend` y otro de `frontend` a pocos minutos de diferencia) nunca compitan intentando `docker compose up --build` al mismo tiempo — el segundo espera a que termine el primero en vez de solaparse.
- El paso de verificación de salud depende de la corrección descrita en [`manual-monitoreo.md`](manual-monitoreo.md) — hoy `/api/health/` es un endpoint vacío que devuelve `200` aunque la base de datos esté caída, así que este paso pasará incluso durante una interrupción real hasta que esa corrección se aplique. Agréguelo a este workflow, pero no confíe en él como única señal hasta entonces.

## 6. Respaldo antes de desplegar

El paso `Backup before deploying` de arriba simplemente invoca el script **ya existente** `infra/scripts/backup_db.ps1` (dump de Postgres + archivo del volumen de medios, con marca de tiempo, retención por defecto de 14 días) — nada nuevo se escribe aquí. Se ejecuta en cada despliegue, así que una versión defectuosa nunca está a más de una restauración de distancia del último estado bueno conocido.

## 7. Reversión (rollback)

- **Reversión de código (ruta principal):** dado que desplegar es solo "revisar `main` en las tres carpetas hermanas, luego `up -d --build`", revertir es la misma operación apuntando al commit bueno conocido anterior — ej. `git -C ../backend reset --hard <sha-anterior>` (y lo mismo para `frontend`/`infra`), y volver a correr el paso de build. Esto puede ser un `workflow_dispatch` manual apuntando a un commit anterior, o un script pequeño que reciba un SHA como argumento.
- **La reversión de datos no es automática.** Si la versión defectuosa incluyó una migración de base de datos, revisar el código anterior *no* deshace esa migración. Use `infra/scripts/restore_db.ps1` contra el respaldo previo al despliegue del paso 6, siguiendo el recorrido completo (y sus advertencias sobre `PII_FIELD_KEY`) en `infra/docs/manuales/manual-respaldo.md`. Trátelo como un paso deliberado que requiere juicio humano — nunca automatice una restauración de datos como parte del pipeline mismo.

## 8. Secretos

Se necesita exactamente un secreto nuevo: un **Personal Access Token de GitHub de tipo fine-grained**, con alcance limitado únicamente al repositorio `infra`, con permiso `Contents: Read and write` (necesario para disparar `repository_dispatch`). Guárdelo como un secreto de repositorio llamado `DEPLOY_DISPATCH_TOKEN` en **tanto** `backend` como `frontend` (no en `infra` — el token necesita *llamar* a la API de infra, así que vive donde está quien llama). Agregue un paso final a cada uno de sus jobs `test`/`build` existentes en `ci.yml`:

```yaml
      - name: Trigger deploy
        if: github.ref == 'refs/heads/main'
        run: |
          curl -X POST \
            -H "Authorization: Bearer ${{ secrets.DEPLOY_DISPATCH_TOKEN }}" \
            -H "Accept: application/vnd.github+json" \
            https://api.github.com/repos/<org-o-usuario>/medicalconsultations-infra/dispatches \
            -d '{"event_type":"deploy"}'
```

No se necesita ningún otro secreto — el runner ya tiene acceso local a `.env` en el servidor (el workflow no lo descarga ni lo genera), y los pasos de despliegue corren como el mismo usuario local que administra el stack manualmente hoy.

## 9. Costo en recursos

Usted señaló que el servidor probablemente tiene especificaciones menores a las de una laptop de desarrollo, con las especificaciones reales aún pendientes — esto se aborda directamente en vez de omitirse:

- El agente del runner en sí es pequeño y está inactivo casi todo el tiempo (es un cliente de consulta ligero, comparable a un agente de sincronización en segundo plano); no agrega carga significativa en estado estable.
- El paso realmente pesado — `docker compose ... up -d --build`, que compila el frontend e instala las dependencias del backend dentro de la imagen — es **exactamente lo que ya corre hoy en esa máquina**, manualmente, cada vez que alguien despliega. Este pipeline no agrega trabajo nuevo al servidor; solo automatiza el *disparo* de un trabajo que ya ocurre ahí.
- Lo que sí agrega: la posibilidad de que dos builds se solapen si dos pushes llegan cerca en el tiempo — mitigado por el grupo `concurrency` del paso 5, que los serializa.
- Una vez que tenga las especificaciones reales del servidor: si los builds corren lento o aparece presión de memoria, lo primero a considerar es (a) si el build de `npm ci`/Vite debería correr con `--max-old-space-size` limitado, y (b) si `docker compose build` necesita un límite de `--memory` por servicio durante la fase de construcción. Ninguno se configura aquí porque sería prematuro sin números reales — queda señalado para cuando los tenga.

## 10. Lista de verificación de extremo a extremo

"Entregado y verificado" para una ejecución del pipeline significa, en concreto:

- [ ] La ejecución de GitHub Actions para `deploy.yml` muestra cada paso en verde — su registro es la bitácora de auditoría (se encuentra en la pestaña **Actions** del repositorio `infra`; el runner autoalojado transmite su salida de vuelta a GitHub igual que lo haría un runner en la nube).
- [ ] `docker compose -f docker-compose.yml -f docker-compose.prod.yml ps` en el servidor muestra los cinco contenedores `running`, con `db`/`cache` (y `backend`/`frontend`/`communications_worker` una vez aplicadas las adiciones de healthcheck de [`manual-monitoreo.md`](manual-monitoreo.md)) reportando `healthy`.
- [ ] `https://<ip-del-servidor>/api/health/` devuelve `200` con verificaciones reales de dependencias pasando (de nuevo, tras la corrección del Manual 2).
- [ ] Una revisión manual rápida — iniciar sesión, abrir un expediente de paciente — o, si es suficientemente ligero para correr sin supervisión, uno de los scripts existentes `infra/scripts/qa_*.ps1` (`qa_live_verification.ps1` o `qa_integration_smoke.ps1` son los más adecuados para una verificación posterior al despliegue; los más completos `qa_full_verification.ps1`/`qa_rbac_matrix.ps1` son más pesados y se ajustan mejor a una ejecución programada o bajo demanda que a cada despliegue individual).

## Vea también

- [`manual-monitoreo.md`](manual-monitoreo.md) — la corrección de la verificación de salud de la que depende el paso de verificación de este pipeline, más un panel para vigilar el stack desplegado después.
- [`manual-despliegue.md`](manual-despliegue.md) / [`deployment-guide.md`](../deployment-guide.md) — el proceso manual que este pipeline automatiza, y el capítulo de red/VPN referenciado arriba.
- [`manual-respaldo.md`](manual-respaldo.md) — el recorrido completo de respaldo/restauración referenciado en la sección de reversión.
