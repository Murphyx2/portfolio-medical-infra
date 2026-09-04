# Docker Container Management

Day-to-day commands for running this stack, how the compose files fit together, how
to change the IP/port a service is bound to, and how to expose the dev frontend to
your home network without exposing it to the internet. All commands below run from
`infra/`.

## 1. How the compose files fit together

- `docker-compose.yml` — base service definitions (`db`, `cache`, `backend`,
  `frontend`). No host ports here; that's left to the overlays below.
- `docker-compose.override.yml` — **dev overlay**, auto-loaded by plain
  `docker compose up` (Compose merges any `docker-compose.override.yml` it finds
  next to the base file). Adds host port bindings, bind-mounts for hot reload, and
  runs `runserver`/`vite dev`.
- `docker-compose.prod.yml` — **prod overlay**, only applied when explicitly
  chained in. Adds gunicorn, TLS via nginx + a `cert-init` helper container, and
  keeps the database/cache off the host network entirely.

```powershell
# Dev (override auto-loaded)
docker compose up -d --build

# Prod (base + prod overlay, explicit)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Dev containers: `mc_db`, `mc_cache`, `mc_backend`, `mc_frontend`.
Prod containers: `mc_prod_db`, `mc_prod_cache`, `mc_prod_backend`, `mc_prod_frontend`.

## 2. Common commands

```powershell
# First-time setup
cp .env.example .env   # then fill in DJANGO_SECRET_KEY, POSTGRES_PASSWORD, PII_FIELD_KEY

# Start / rebuild everything
docker compose up -d --build

# Stop (keeps volumes — data is safe)
docker compose down

# Status / health
docker compose ps

# Logs (all services, or one)
docker compose logs -f
docker compose logs -f backend

# Rebuild one service after code or dependency changes
docker compose up -d --build backend
# If only source under a bind-mounted volume changed (no new deps), a plain
# restart is enough and faster:
docker compose up -d --force-recreate backend

# Shell into a container
docker compose exec backend sh
docker compose exec db psql -U <POSTGRES_USER> -d <POSTGRES_DB>

# Django management commands
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py create_admin --username admin --email admin@example.com --password "..."
docker compose exec backend python manage.py reencrypt_pii --old-key <OLD_KEY>
```

> **Destructive — think twice:** `docker compose down -v` also deletes the named
> volumes (`pgdata`, `media_volume`), permanently wiping every patient record and
> uploaded image. Only run it when you explicitly intend to reset the database
> (e.g. a throwaway dev environment). For real data, back up first — see
> `infra/docs/backups.md`.

## 3. Changing IP / port bindings

Host ports live only in the overlay files, never the base file:

| Service  | Dev binding (`docker-compose.override.yml`) | Prod binding (`docker-compose.prod.yml`) |
|----------|-----------------------------------------------|-------------------------------------------|
| db       | `127.0.0.1:5432:5432` (loopback only)          | not published                             |
| cache    | `127.0.0.1:6379:6379` (loopback only)          | not published                             |
| backend  | `127.0.0.1:8000:8000` (loopback only)          | not published (nginx proxies internally)  |
| frontend | `127.0.0.1:5173:5173` (loopback only)          | `443:443`, `80:80` (all interfaces)       |

All four dev services bind to loopback only — the dev server runs with
`DEBUG=true` and no HTTPS, so nothing here is reachable from another machine
by default. See §4 below for the deliberate, opt-in way to open the
frontend/backend to your LAN when you actually want that.

A `ports:` entry follows `HOST_IP:HOST_PORT:CONTAINER_PORT` — only the first two
segments are yours to change without touching application code. `HOST_IP` is
optional; omitting it binds to `0.0.0.0`, i.e. every network interface on the
host, not just `localhost` — that's exactly what §4's LAN override does on
purpose, and exactly what none of the dev services do by default anymore.

**To change a port:** edit the `ports:` line for that service in the relevant
compose file, e.g.:

```yaml
backend:
  ports:
    - "9000:8000"   # host port 9000 -> container's 8000
```

Then apply it:

```powershell
docker compose up -d --force-recreate backend
```

**Downstream updates to remember:**
- Changed the backend's host port/origin? Update `DJANGO_ALLOWED_HOSTS` and
  `DJANGO_CORS_ALLOWED_ORIGINS` in `.env` if the origin browsers hit changed, and
  `PROXY_TARGET` if you run the frontend outside Docker against this backend.
- Changed the frontend dev port? That's a code change, not just compose —
  `server.port` in `frontend/vite.config.ts` — plus any CORS origin referencing
  `:5173`.
- Changing a bind IP so `db`/`cache` are reachable beyond loopback is a
  security-relevant change (this stack holds patient PII) — only do it
  deliberately, and never in prod (they intentionally have no published port
  there).

## 4. Exposing the dev frontend to your home network (LAN only)

The dev overlay binds the frontend (`127.0.0.1:5173:5173`) and backend
(`127.0.0.1:8000:8000`) to loopback only by default — nothing here is reachable
from another device until you deliberately republish the port on `0.0.0.0`.
Don't edit `docker-compose.override.yml` for this (it's meant to stay
loopback-only for everyone); add a local, gitignored override file instead:

```yaml
# docker-compose.override.local.yml (not committed — add it to your local
# .gitignore or a global excludes file if it isn't already covered)
services:
  frontend:
    ports:
      - "5173:5173"   # no host-IP prefix -> binds 0.0.0.0
```

```powershell
docker compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.override.local.yml up -d
```

No code, `.env`, or CORS changes are needed beyond that. The frontend talks to the
backend via a same-origin proxy (`/api`, `/media` in `vite.config.ts`), so a
browser on another device only ever talks to the Vite dev server directly — the
backend's `Host` header stays `backend` regardless of what IP you used to reach
the page. (Add the same block for `backend` too, only if you specifically need
to hit the API directly rather than through the frontend's proxy.)

Once the port is republished on `0.0.0.0`, the remaining steps are the same as
before:

**Steps:**

1. **Find your LAN IP** on the host machine:
   ```powershell
   ipconfig
   ```
   Look for the `IPv4 Address` under your active Wi-Fi or Ethernet adapter, e.g.
   `192.168.1.42`.

2. **Open the port in Windows Firewall**, scoped to the **Private** network
   profile only:
   ```powershell
   New-NetFirewallRule -DisplayName "MedicalConsultations Dev Frontend" `
     -Direction Inbound -LocalPort 5173 -Protocol TCP -Action Allow -Profile Private
   ```
   Only add a rule for port `8000` too if you specifically need to hit the API
   directly — normal use goes through the frontend's proxy and doesn't need it.

3. **Browse from another device** on the same network:
   ```
   http://192.168.1.42:5173
   ```

### From a phone

Same idea, no extra setup beyond the two steps above:

1. Connect your phone to the **same Wi-Fi network** as the host machine (not a
   guest network — see note below).
2. Open a browser and go to `http://<host-LAN-IP>:5173`, e.g.
   `http://192.168.1.42:5173`.

If it doesn't load:
- Some routers put phones/guests on an isolated SSID with **client/AP isolation**
  enabled, which blocks device-to-device traffic even on the same Wi-Fi — connect
  the phone to the main network, not a guest one.
- The host's LAN IP can change after a reboot or DHCP renewal — rerun `ipconfig`
  on the host to confirm it before assuming the firewall is the problem.
- Confirm the firewall rule exists and is enabled:
  ```powershell
  Get-NetFirewallRule -DisplayName "MedicalConsultations Dev Frontend" |
    Select-Object DisplayName, Enabled, Profile, Direction
  ```

**Security — read before doing this:**

- ⚠️ **Never forward this port on your router.** A firewall rule scoped to
  `-Profile Private` only opens it on your home network — port-forwarding on the
  router would expose it to the entire internet instead.
- Keep the firewall rule's profile **Private**, never `Public`/`Domain`/`Any` —
  otherwise the same rule also applies on untrusted networks (coffee shop wifi,
  etc.) if this laptop ever joins one.
- Dev traffic is plain HTTP — unencrypted on the wire. Fine for quick testing on a
  trusted home network, but this stack handles patient PII, so don't leave it
  exposed longer than needed and don't use this setup for anything beyond casual
  local testing. For anything more persistent or multi-user, use the TLS-terminated
  prod overlay instead (`docker-compose.prod.yml` + `frontend/nginx.conf`).
- To revert:
  ```powershell
  Remove-NetFirewallRule -DisplayName "MedicalConsultations Dev Frontend"
  ```

**Troubleshooting:** if you access the dev server via a hostname (e.g. an mDNS
`.local` name) instead of a bare IP and get a Vite *"This host is not allowed"*
error, that's `server.allowedHosts` in `vite.config.ts` — a Vite 6 security check
that only applies to hostnames, not raw IPs. Add the specific hostname to
`allowedHosts` rather than disabling the check.

## 5. Environment variables reference

Copy `infra/.env.example` to `infra/.env` and fill these in — `.env` is
gitignored and must never be committed.

| Variable | Purpose |
|----------|---------|
| `POSTGRES_PORT` | Port Postgres listens on inside its container (host mapping is set in the compose overlay, not here). |
| `REDIS_PASSWORD` | Required in prod (`cache` requires auth there); same var used by dev, unset there. |
| `PROXY_TARGET` | Vite dev proxy target for `/api` — only relevant if you run the frontend *outside* Docker against a Dockerized backend. Inside Docker it's overridden by the compose overlay. |
| `DJANGO_ALLOWED_HOSTS` | Hostnames Django will accept `Host:` headers from. |
| `DJANGO_CORS_ALLOWED_ORIGINS` | Origins allowed to make cross-origin API calls (not needed for same-origin proxied requests). |

## 6. Troubleshooting

- **Port already in use:** `docker compose ps` to see what's already bound, or on
  Windows: `Get-NetTCPConnection -LocalPort 5173` to find the conflicting process.
- **Code changes not showing up:** confirm you're editing the bind-mounted source
  (`../backend`, `../frontend`) and not a stale built image; `docker compose up -d
  --force-recreate <service>` after code-only changes, `--build` after dependency
  changes. Don't assume a passing build means the *running* container is serving
  the new code — verify in the browser/API response.
- **Lost data after `down -v`:** volumes (`pgdata`, `media_volume`) hold every
  patient record and uploaded image with no built-in redundancy — see
  `infra/docs/backups.md` for restore instructions.
