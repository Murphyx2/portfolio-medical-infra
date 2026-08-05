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
                        │  patients records medicines   │
                        │  appointments                 │
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
| `doctors`    | Doctor profile, contact, specialty, license, schedule/presence        | doctors-service|
| `patients`   | Patient PII (encrypted), address, contact, optional email             | patients-service|
| `records`    | Medical records, consultation logs, image attachments, treatments     | records-service|
| `medicines`  | Medicine: generic term, commercial name, concentration                | medicines-service|
| `appointments`| Appointments created by doctor or receptionist                       | appointments-service|

Each app is **loosely coupled**: it owns its models, serializers, views, URLs, and tests,
and exposes a clear HTTP API surface. This is the seed of a future microservice split.

## 3. Modular Monolith → Microservices Strategy

- **Phase-out boundaries:** apps communicate only via their public URLs, never by
  importing another app's models directly where avoidable. Migrations stay isolated.
- **Extraction path:** to split `appointments` into a service, add an
  `appointments-service` container, expose the same OpenAPI contract, route `/api/appointments/*`
  to it, then remove the app from the monolith.
- **Shared infrastructure ready today:** Redis, JWT (stateless auth), docker network,
  PostgreSQL already supports multi-service topology.
- **Constraints for smooth transition:**
  1. Do not cross-import models between apps without a documented exception.
  2. All cross-app data access goes through serializers / service-layer functions.
  3. Keep a single OpenAPI schema; each app publishes its own router prefix.

## 4. Security Design

- **AuthN:** JWT (access short-lived + refresh). Passwords via Django PBKDF2/Argon2.
- **AuthZ:** role-based permissions (Admin, Doctor, Receptionist, IT, Nurse,
  Center Manager) enforced per endpoint with custom permission classes.
- **Data at rest:** sensitive patient PII encrypted field-level (`cryptography`).
- **Audit:** every read/write of patient records logged (who, when, what, IP).
- **Transport:** HTTPS in prod; secure cookie flags; CSP; rate limiting on auth & APIs.
- **Secrets:** never committed; loaded from environment (`infra/.env` from `.env.example`).

## 5. Deployment Topology (laptop / Docker Compose)

| Service   | Image             | Notes                                   |
|-----------|-------------------|-----------------------------------------|
| `db`      | postgres:16-alpine| named volume for data                   |
| `cache`   | redis:7-alpine    | cache + future Celery broker            |
| `backend` | Django + gunicorn | volumes for dev (runserver)             |
| `frontend`| Vite dev / nginx  | dev proxy `/api` → backend; prod nginx static + proxy |

Dev mode: `docker compose up`; prod mode: build frontend static, nginx serves it and
reverse-proxies `/api`.

## 6. CI/CD (GitHub Actions, in infra repo)

- **CI:** run backend pytest; run frontend build (and later tests); lint.
- **CD:** build & tag Docker images; (later) push to registry / deploy to laptop.
