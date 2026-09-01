# Service Monitoring

> Status: **reference design, not yet implemented.** This document answers "do we have monitoring today?" (no) and lays out what to add, with literal copy-paste-ready code/compose content for whenever you decide to build it. Nothing described here has been created in the repos yet.

## 1. Current state

There is no monitoring of any kind today. Specifically, verified directly against the code:

- **`/api/health/`** (`backend/config/urls.py:25`) is a bare inline lambda:
  ```python
  path("api/health/", lambda request: JsonResponse({"status": "ok"}), name="health"),
  ```
  It checks nothing. It returns `200 {"status": "ok"}` as long as the Django/gunicorn *process* is alive and routing requests — even if Postgres or Redis is completely down. It exists today purely as a one-time manual "did the deploy work" `curl` check in the deployment docs, not as an ongoing target for anything.
- **Docker `HEALTHCHECK`** only exists on `db` and `cache` (`infra/docker-compose.yml` — `pg_isready` / `redis-cli ping`, every 5s). `backend`, `frontend`, and `communications_worker` have **no** healthcheck directive at all; `depends_on: condition: service_healthy` only gates on `db`/`cache` being up, nothing observes whether `backend` itself is actually serving.
- **No logging pipeline.** No `LOGGING` dict exists in any of `backend/config/settings/{base,dev,prod,test}.py` — Django falls back to default stderr logging. No file/rotating handler, nothing shipped off-host.
- **No metrics/APM tooling.** Confirmed by search: no Sentry, Prometheus, Grafana, Datadog, New Relic, Elastic, Loki, statsd, or OpenTelemetry anywhere in any of the three repos.
- **`AuditLog`** (`apps/core/models.py`) exists but is a **compliance/security trail** of user actions (who read/edited/deleted which record) — not a system-health signal. Don't conflate the two.
- **The only self-healing that exists** is `restart: unless-stopped` on every service. This is entirely passive: if `communications_worker`'s loop starts silently failing every cycle, or a container enters a restart-loop, nothing tells a human — the containers just keep restarting forever.

No existing doc (`architecture.md`, `deployment-guide.md`, `PROGRESS.md`) previously flagged this as a tracked gap — this document is the first place it's written down.

## 2. Two prerequisite fixes

Both are small, targeted code/config changes. Apply these *before* pointing a dashboard at the stack — otherwise the dashboard will report green during a real outage, which is worse than no dashboard.

### 2a. Make `/api/health/` actually check its dependencies

Move it out of `urls.py` into a real view in `apps/core/`, e.g. `apps/core/views.py`:

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

(Uses `CACHES["default"]` — this project's `django.core.cache.backends.redis.RedisCache`, `backend/config/settings/base.py:141` — via Django's own cache API rather than a Redis client library, since none is a project dependency here.)

And in `backend/config/urls.py`, replace the lambda:

```python
from apps.core.views import health_check
...
path("api/health/", health_check, name="health"),
```

This is what makes both the deploy pipeline's post-deploy check ([`cicd-deployment-pipeline.md`](cicd-deployment-pipeline.md) §5/§10) and the dashboard monitor below actually mean something.

### 2b. Add Docker healthchecks to the remaining three services

In `infra/docker-compose.prod.yml`, mirroring the existing `db`/`cache` pattern:

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

`communications_worker` has no HTTP server to probe — its own compose command (`infra/docker-compose.yml`) is a `sh -c "while true; do ...; sleep 60; done"` loop. Add a `touch /tmp/comms_worker_alive` at the top of each loop iteration so the healthcheck has something to look at; without that one-line addition to the loop command, a Docker healthcheck can't distinguish "hung" from "running."

`frontend` (nginx) doesn't strictly need one for correctness — nginx dying takes the whole container down anyway, which Docker already reports as `Exited` — but adding a trivial one keeps the "all containers report healthy" check in the CD pipeline uniform:

```yaml
  frontend:
    healthcheck:
      test: ["CMD", "wget", "--no-check-certificate", "-qO-", "https://localhost/"]
      interval: 15s
      timeout: 5s
      retries: 5
```

## 3. Uptime Kuma as a new compose service

[Uptime Kuma](https://github.com/louislam/uptime-kuma) is a single self-hosted container: a status dashboard with built-in uptime monitors, response-time graphs, and notification integrations, storing its own state in SQLite. It fits this deployment well — one more lightweight container, no external dependency, no separate database to run, and a UI a non-DevOps developer can operate without learning a query language (the alternative, Prometheus + Grafana, is more powerful but is a small metrics platform in its own right — multiple containers, its own storage/retention tuning, and a steeper learning curve for a single-server clinic deployment where "is it up, and did anyone get told when it wasn't" is the actual requirement).

Add to `infra/docker-compose.prod.yml`:

```yaml
  monitor:
    image: louislam/uptime-kuma:1
    container_name: mc_prod_monitor
    restart: unless-stopped
    volumes:
      - kuma_data:/app/data
    ports:
      - "127.0.0.1:3001:3001"   # bind to loopback only — see §4 on remote access

volumes:
  kuma_data:
```

> **Do not** publish this port more broadly (e.g. `"3001:3001"`, or the server's LAN IP) without deliberately deciding to — binding to `127.0.0.1` here means it's reachable only from *on* the server itself. §4 below covers how you actually get to it, which is deliberately not "open it on the LAN."
>
> If you do want it reachable from other machines on the clinic LAN directly (not just via VPN), bind it to the server's LAN IP instead of `127.0.0.1` — but never to `0.0.0.0`/all interfaces, for the same reason the app itself is never exposed that way.

First-run setup, once the container is up:

1. From the server, open `http://localhost:3001` and complete the setup wizard (create the admin account — treat these credentials with the same seriousness as any other admin account here).
2. Add one **HTTP(s) monitor** per thing worth watching:
   - `https://localhost/api/health/` (or the server's own IP) — this is the one that matters most once §2a lands, since it reflects DB+Redis health, not just "gunicorn is up."
   - `https://localhost/` — confirms the frontend/nginx is actually serving pages, not just that the container exists.
   - Optionally, a **Docker container monitor** (Kuma supports this via the Docker socket) for each of the five app containers, so a crash-looping container shows up even if its HTTP surface happens to still respond.
3. Add a **notification** (Settings → Notifications → Setup Notification): choose **SMTP/Email**, and reuse the *existing* mailbox already configured for the Comunicaciones module (`EMAIL_HOST` / `EMAIL_PORT` / `EMAIL_HOST_USER` / `EMAIL_HOST_PASSWORD` / `EMAIL_USE_TLS` in `.env`) rather than provisioning a second mailbox — no new secret is needed. Attach that notification to each monitor.

## 4. Remote access

**Yes, you can reach this remotely — through the VPN, not by opening the dashboard's port to the internet, and not primarily by remoting into the server's desktop either.**

The dashboard is bound to the server's loopback/LAN interface only (§3), by design — exactly the same "never expose this machine to the public internet" rule the deployment manual already applies to the app itself (`manual-despliegue.md` Chapter 8 / `deployment-guide.md`'s network chapter: no port-forwarding, UPnP/DMZ off). The recommended way to reach it from outside the clinic is the **same VPN already documented there** for legitimate remote access (e.g. WireGuard): once your laptop is connected to that VPN, it behaves as if it's physically on the clinic LAN, and you browse straight to `http://<server-lan-ip>:3001` (if you bound it to the LAN IP rather than loopback) exactly as you'd reach the app itself at `https://<server-lan-ip>`.

Why the VPN and not an RDP/remote-desktop session into the server, as a primary method:

- **One investment, everything covered.** The VPN already gets you the app, the dashboard, and (if ever needed) an RDP/SSH session too — it's strictly more capable, not an either/or.
- **RDP is itself a commonly-attacked port** and, like everything else here, must never be exposed directly to the internet — so reaching it remotely *also* requires the VPN (or a similarly tunneled path) regardless. There's no path where RDP is reachable but the VPN isn't also required, so RDP adds a step rather than saving one.
- **Resource cost.** A full interactive remote-desktop session (rendering a desktop, keeping a user session alive) is a heavier ask of hardware you've flagged as possibly resource-constrained, just to look at a status page. A VPN tunnel carrying a single browser request is much cheaper.

If the VPN genuinely isn't set up yet and you need to check the dashboard *today*, an RDP session into the server (over the LAN only, never opened to the internet) and loading `http://localhost:3001` locally from inside that session works as a stop-gap — just don't treat it as the long-term plan; set up the VPN and use that instead.

## 5. What it alerts on

With the setup in §3, Kuma will notify (by email, to the address(es) you configure in its notification settings) when:

- A monitored URL stops returning a successful status (the site is down, or `/api/health/` starts returning `503` because the database or Redis check failed).
- Response time crosses whatever threshold you set per-monitor (useful for catching "it's up but struggling" before it becomes "it's down").
- A monitored container (if you added Docker container monitors) stops, exits, or enters a restart loop.

It also gives you a public-facing-optional status page feature — not relevant here since this stays LAN/VPN-only, but worth knowing it exists if a future need for a staff-visible status board comes up.

## 6. Maintenance

Uptime Kuma's own SQLite data (`kuma_data` volume) holds only monitor configuration and historical uptime/response-time data — no patient data, nothing PII-sensitive, nothing compliance-relevant. Treat it as low-stakes and recreatable: back it up opportunistically (a simple periodic `docker run --rm -v medicalconsultations-prod_kuma_data:/data -v <backup-dir>:/backup alpine tar czf /backup/kuma_data.tar.gz /data` is enough) rather than folding it into `backup_db.ps1`'s PII-aware retention/restore flow — conflating the two would blur what actually needs the careful `PII_FIELD_KEY`-aware handling described in `manual-respaldo.md`.

## See also

- [`cicd-deployment-pipeline.md`](cicd-deployment-pipeline.md) — the deploy pipeline whose verification step depends on the `/api/health/` fix in §2a here.
- [`manual-despliegue.md`](manuales/manual-despliegue.md) / [`deployment-guide.md`](deployment-guide.md) — the network/VPN chapter this document's remote-access guidance builds on.
- [`manual-respaldo.md`](manuales/manual-respaldo.md) — the PII-aware backup/restore process that Kuma's own low-stakes data should stay separate from.
