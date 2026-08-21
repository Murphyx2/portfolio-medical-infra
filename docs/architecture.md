# MedicalConsultations — Architecture

## 1. System Overview

A medical consultations management system for one or multiple medical centers.
Django REST API (modular monolith) + React SPA, orchestrated with Docker Compose,
PostgreSQL for persistence and Redis for caching.

```
                        ┌──────────────────────────────┐
                        │         Frontend             │
                        │   React + Vite + TS (SPA)     │
                        │   i18n: EN / ES              │
                        └──────────────┬───────────────┘
                                       │ HTTPS /api (JWT)
                        ┌──────────────┴───────────────┐
                        │         Backend (Django)      │
                        │  config/  +  apps/            │
                        │  accounts centers doctors     │
                        │  ars      patients records    │
                        │  medicines appointments      │
                        │  services rooms  encounters   │
                        └──────┬───────────────┬────────┘
                               │               │
                     ┌─────────┴───┐    ┌──────┴────────┐
                     │ PostgreSQL  │    │ Redis (cache) │
                     │    16       │    │    7          │
                     └─────────────┘    └───────────────┘
```

## 2. Backend Modules (apps)

| App          | Responsibility                                                       | Future service |
|--------------|----------------------------------------------------------------------|----------------|
| `accounts`   | Custom user, roles, JWT auth, RBAC permissions                        | auth-service   |
| `centers`    | Medical centers; doctor-to-center bindings (0..N)                     | centers-service|
| `ars`        | Insurance companies (ARS) + their programs (ARSProgram)               | ars-service    |
| `doctors`    | Doctor profile, contact, specialty, license, schedule/presence        | doctors-service|
| `patients`   | Patient PII (encrypted), address, contact, optional email             | patients-service|
| `records`    | Medical records, consultation logs, image attachments, treatments     | records-service|
| `medicines`  | Medicine: generic term, commercial name, concentration                | medicines-service|
| `appointments`| Appointments created by doctor or receptionist                       | appointments-service|
| `services`   | Service catalog (Service + ServiceType), pricing, requires-doctor/diagnosis flags | services-service |
| `rooms`      | Physical rooms + room-type catalog                                     | rooms-service  |
| `encounters` | Patient admissions/visits (Encounter) with diagnoses + services rendered, lifecycle (admit/complete/cancel), daily numbering | encounters-service |

Each app is **loosely coupled**: it owns its models, serializers, views, URLs, and tests,
and exposes a clear HTTP API surface. This is the seed of a future microservice split.

The `encounters` app is the deepest module — a nested writable serializer with
diff-based diagnosis/service updates, a collision-retrying `generate_encounter_number`,
and an admit/cancel/complete lifecycle with same-day conflict detection. The `rooms`
and `services` apps are shallow CRUD with reference-list caching. `patients` carries
field-level PII encryption with plaintext helper columns (`search_name`, `*_last4`,
`*_hash`) kept in sync in `save()` so search never touches an encrypted column.

## 3. Modular Monolith → Microservices Strategy

- **Phase-out boundaries:** apps communicate only via their public URLs, never by
  importing another app's models directly where avoidable. Migrations stay isolated.
- **Extraction path:** to split `appointments` into a service, add an
  `appointments-service` container, expose the same OpenAPI contract, route `/api/appointments/*`
  to it, then remove the app from the monolith. (Note: `frontend/nginx.conf` currently
  hardcodes a single `upstream backend` for all of `/api/` — per-prefix routing must be
  added to nginx before the first split.)
- **Shared infrastructure ready today:** Redis, JWT (stateless auth), docker network,
  PostgreSQL already supports multi-service topology.
- **Constraints for smooth transition:**
  1. Do not cross-import models between apps without a documented exception.
  2. All cross-app data access goes through serializers / service-layer functions.
  3. Keep a single OpenAPI schema; each app publishes its own router prefix.

Each app publishes its own router prefix under `/api/` (`config/urls.py`):

| Prefix                    | App          |
|---------------------------|--------------|
| `/api/auth/`              | accounts     |
| `/api/centers/`, `/api/bindings/` | centers     |
| `/api/ars/`               | ars          |
| `/api/doctors/profiles/`, `/api/doctors/schedules/` | doctors |
| `/api/patients/`          | patients     |
| `/api/medical-records/`, `/api/consultation-logs/`, `/api/images/` | records |
| `/api/medicines/`         | medicines    |
| `/api/appointments/`      | appointments |
| `/api/services/`, `/api/service-types/` | services     |
| `/api/rooms/`, `/api/room-types/`      | rooms        |
| `/api/encounters/`        | encounters   |

Plus `/api/health/` (public), `/api/schema/` + `/api/docs/` (ADMIN/IT only),
and `/media/<path>?token=…` (HMAC-signed token, 1h TTL).

## 4. Security Design

- **AuthN:** JWT via `djangorestframework-simplejwt`. Access token is short-lived and
  held **in memory only** on the frontend; the refresh token lives in an httpOnly,
  `SameSite=Strict`, path-scoped (`/api/auth/`) cookie, rotated on every refresh and
  blacklisted on logout.
- **AuthZ:** role-based permissions (Admin, Doctor, Receptionist, IT, Nurse,
  Center Manager) enforced per endpoint with custom permission classes. **Only ADMIN
  gets `is_staff`/`is_superuser`** — IT is force-stripped in `User.save()`. Doctors are
  center-scoped via `user_accessible_center_ids()`; IT/CENTER_MANAGER get masked PII
  output.
- **Data at rest:** sensitive patient PII encrypted field-level (`cryptography`/Fernet),
  keyed by `PII_FIELD_KEY`. Search uses plaintext helper columns (`search_name`,
  `*_last4`, `*_hash`) — no query ever filters on an encrypted column. Rotating the key
  requires `manage.py reencrypt_pii --old-key <OLD_KEY>`.
- **Audit:** every create/update/delete/restore is logged through
  `apps/core/services.py::log_audit` into `AuditLog` (who, when, what, IP); Django admin
  mutations get the same treatment via `AuditModelAdmin`.
- **Soft delete:** the 17 core entities are never hard-deleted — "delete" sets
  `active`/`is_active=False` (`deactivate_with_cascade`); restore is **admin-only**
  (`can_view_inactive()`). Active-only visibility is the default for everyone.
- **Media:** `/media/` is never served statically — `ProtectedMediaView` requires an
  HMAC-signed token (1h TTL, path-traversal guarded); no token = 404.
- **Transport & cache:** HTTPS in prod (nginx redirect + HSTS); `NoStoreMiddleware`
  forces `Cache-Control: private, no-store` on every `/api/` and `/media/` response.
- **Secrets:** never committed; loaded from environment (`infra/.env` from `.env.example`).
  Prod settings fail fast on missing/default `SECRET_KEY`, `ALLOWED_HOSTS`, `PII_FIELD_KEY`.

## 5. Deployment Topology (laptop / Docker Compose)

| Service   | Image             | Notes                                   |
|-----------|-------------------|-----------------------------------------|
| `db`      | postgres:16-alpine| named volume for data                   |
| `cache`   | redis:7-alpine    | cache + future Celery broker            |
| `backend` | Django + gunicorn | volumes for dev (runserver); whitenoise serves collected static assets in-process (no filesystem/volume needed for `STATIC_ROOT`) |
| `frontend`| Vite dev / nginx  | dev proxy `/api` → backend; prod nginx static + proxy. `client_max_body_size 6m` (just above the backend's 5MB record-image cap); `/static/` and `/admin/` proxy to `backend` like `/api/` (both previously fell through to the SPA catch-all) |

Dev mode: `docker compose up` (auto-loads `docker-compose.override.yml`); prod mode:
`docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` — built frontend
static, nginx serves it and reverse-proxies `/api`.

Note: dev and prod share a single `docker-compose.yml` base (image, env, healthchecks,
volumes); `docker-compose.override.yml` adds dev-only bind mounts/ports/runserver and
`docker-compose.prod.yml` adds prod-only gunicorn/TLS/cert-init. A topology change goes
in the base unless it is dev-only or prod-only.

## 6. CI/CD (GitHub Actions)

- Per-repo workflows live next to the code: `backend/.github/workflows/ci.yml`,
  `frontend/.github/workflows/ci.yml`, `infra/.github/workflows/ci.yml`. Each triggers on
  pushes and PRs to `dev`/`main` — a push to any repo fires its own gate.
- **Backend CI:** `manage.py check` + pytest.
- **Frontend CI:** `npm ci` + `npm run build` (type-check + vite build) + vitest.
- **Infra CI:** validates both dev (`docker-compose.yml` + override) and prod
  (`docker-compose.yml` + `docker-compose.prod.yml`) compose configs.
- **CD:** build & tag Docker images; (later) push to registry / deploy to laptop.
