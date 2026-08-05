# MedicalConsultations — Project Progress

> Living document: original specification, design decisions, and a running log of progress.

## Overview

MedicalConsultations is a medical consultations management system for one or multiple
medical centers. It manages doctors, patients, medical records (including images and
consultation logs), medicines, and appointments. Access is role-based and patient data
is handled under international security standards.

## Color Palette (BluePalette.png)

| Hex       | Usage                          |
|-----------|--------------------------------|
| `#E3F2FD` | Lightest / background tint     |
| `#90CAF9` | Light accent                    |
| `#2196F3` | Primary color                   |
| `#0D47A1` | Dark / text & emphasis          |

## Roles

- **Admin** — full system administration, grants access, manages centers/roles
- **Doctor** — manages their schedule, patients, medical records, appointments
- **Receptionist** — manages appointments, patient records intake
- **IT** — system maintenance, infrastructure
- **Nurse** — supports patient care (assists with records/logs)
- **Center Manager** — manages a specific medical center's operations

## Core Modules

1. **Doctors** — full name, contact information, specialty, license, optional presence
   schedule per center. A doctor is bound to **zero or more** medical centers.
2. **Patients** — address, contact information, optional email, medical records
   (doctor-written), optional images, current treatment / medicine / doses, and a
   consultation log per visit.
3. **Medicines** — generic (medical) term, commercial name, concentration.
4. **Appointments** — created by a doctor or a receptionist for a patient.

## Technology Decisions

| Concern              | Decision                                                            |
|----------------------|---------------------------------------------------------------------|
| Backend              | Python + Django (LTS) + Django REST Framework                        |
| Frontend             | React + Vite + TypeScript (SPA)                                     |
| Database             | PostgreSQL 16                                                       |
| Cache / message      | Redis 7 (cache; later Celery broker)                                |
| Auth                 | JWT tokens (djangorestframework-simplejwt)                          |
| API language         | English default + Spanish (i18n-ready, react-i18next)               |
| Architecture         | Modular monolith now, microservice-ready                            |
| Deployment           | Docker Compose on a laptop, portable to CI/CD                       |
| Tests                | pytest (backend), vitest/RTL (frontend, later)                      |
| Security             | RBAC, field-level PII encryption, audit log, rate limiting, HTTPS   |

### Why PostgreSQL + Redis

PostgreSQL pairs best with Django's ORM (JSONB, full-text search, strong integrity for
medical data). Redis serves as the cache and doubles as the Celery broker for future
async work (image processing, notifications, emails). No better alternative at this scale.

## Repository Layout (3 repos)

```
MedicalConsultations/
├── infra/      repo: medicalconsultations-infra    (compose, env templates, docs, CI/CD)
├── backend/    repo: medicalconsultations-backend  (Django API)
└── frontend/   repo: medicalconsultations-frontend (React SPA)
```

Each app in `backend/apps/` is a candidate future microservice:
`accounts, centers, doctors, patients, records, medicines, appointments`.

---

## Progress Log

### 2026-08-05 — Step 1: Scaffold & 3 repos ✅
- Created workspace folder structure (`infra/`, `backend/`, `frontend/`).
- `git init` on `main` for all three repos.
- Wrote PROGRESS.md, README files, architecture doc, env template, gitignores.
- Initial commit per repo (amended): infra `d1084e4`, backend `902768b`, frontend `82c493a`.

### 2026-08-05 — Step 2: Docker + project skeletons ✅
- `docker-compose.yml`: db (postgres:16), cache (redis:7), backend (Django runserver), frontend (Vite dev) — all 4 containers healthy.
- Django `config/` with settings split `base/dev/prod`; 7 apps created under `apps/`.
- Custom `accounts.User` (roles Admin, Doctor, Receptionist, IT, Nurse, Center Manager) + migration.
- Frontend: Vite+React+TS with palette theme tokens, i18n (en/es), API client, Dockerfile(s), nginx.conf. `npm run build` passes.
- Verified: `docker compose up` boots; `/admin/` responds; Vite serves 200.
- Commits: infra `096a054`, backend `39f1fd8`, frontend `cbf7e4f`.

### 2026-08-05 — Step 3: Backend MVP ✅
- Models for all apps: User+roles, MedicalCenter, DoctorCenterBinding (admin-approved), DoctorProfile, DoctorSchedule, Patient (PII encrypted), MedicalRecord + ConsultationLog + RecordImage, Medicine, Appointment.
- JWT auth (login/refresh/me), user management (Admin/IT), RBAC permission classes per role.
- Field-level PII encryption (Fernet, `apps/core/fields.py`) verified at rest in Postgres.
- Audit log app (`AuditLog` + `AuditMixin`), DRF throttling (incl. login), hardened prod settings.
- Redaction: IT sees masked patient PII; receptionist/IT see masked clinical record content.
- `create_admin` management command for reproducible setup.
- Tests: 31 passed (auth, roles, CRUD, permission matrix, encryption-at-rest, redaction).
- Verified end-to-end via live stack: login → center → doctor → patient → medicine → appointment → record → consultation log; PII ciphertext confirmed in Postgres.
- Commits: backend `40f0f5a` (MVP), `51bc6a4` (token blacklist + image validation), `3f76b4f` (admin image upload); infra `0325a37` (PII key env template).

### 2026-08-05 — Step 4: Frontend MVP ✅
- Auth flow: login (JWT), token refresh, protected routes, role-aware navigation.
- Pages: Dashboard, Patients, Doctors, Centers, Medicines, Users (Admin/IT), Appointments (create + cancel/complete), Medical Records (create, detail, image upload, consultation logs).
- i18n EN default + ES (react-i18next), language switcher; palette theming across the app.
- API client with automatic token refresh and retry; multipart upload for record images.
- Verified: `npm run build` passes; Vite dev proxy (`/api`, `/media`) reaches backend container; login + `/api/auth/me` work through the proxy.
- Commits: frontend `ae7e889` (MVP), `33c93a3` (rotate-refresh persistence); infra `4263b7b` (compose frontend env + progress).

### 2026-08-05 — Step 5: Security review + CI/CD ✅
- JWT token blacklist enabled (rotation blacklists old refresh tokens); frontend persists rotated refresh tokens.
- Record image upload validation (size ≤ 5 MB, image extensions only); Admin allowed to upload.
- Django `check --deploy` passes (only warning from intentionally short test key).
- GitHub Actions in infra: `backend-ci.yml` (checks + pytest), `frontend-ci.yml` (type-check + build).
- Full README quick-start for fresh clone of the 3 repos.
- Verified: clean `docker compose down/up` boots all 4 services; image upload → `/media/...` serves 200; record lists the image.
- Hotfix: frontend `AuthProvider` was never mounted → Login page crashed; wrapped app in `AuthProvider` in `main.tsx`.
- Added Swagger/OpenAPI via `drf-spectacular`: `/api/docs/` (Swagger UI) + `/api/schema/` (29 paths, JWT auth) — public schema, docs at `/api/docs/`.
- Fixed login `ERR_NAME_NOT_RESOLVED`: dev browser now uses relative `/api` via Vite proxy; proxy target moved to server-side `PROXY_TARGET` env (`http://backend:8000/api`), `VITE_API_BASE_URL` no longer baked into the client bundle.
- Added `TEST_USERS.md` with a working account per role (admin, doctor, receptionist, nurse, it, cm) — all verified logging in.
- Commits: infra `8b3e453` (CI + README), `49ef3d9` (progress finalize), `9301d30` (AuthProvider/Swagger notes), `407445f` (PROXY_TARGET + TEST_USERS), `37931ae` (handoff docs); backend `5445a85` (Swagger/OpenAPI); frontend `b4610b0` (AuthProvider), `0e65a83` (proxy fix).

## Project complete — MVP delivered
All 5 steps done. Backend (Django) 31 tests passing; frontend builds; stack runs via Docker Compose with PostgreSQL + Redis cache; patient PII encrypted at rest; RBAC + audit + throttling in place; CI/CD ready to activate on push.

---

## Current Handoff State (2026-08-05)

Everything below was verified against the live stack. All three repos are clean (`git status` empty).

### Repos & latest commits
| Repo       | Path                                                                                            | Latest commit |
|------------|-------------------------------------------------------------------------------------------------|---------------|
| infra      | `infra/` (compose, env, docs, CI, scripts)                                                      | `37931ae`     |
| backend    | `backend/` (Django API)                                                                         | `5445a85`     |
| frontend   | `frontend/` (React SPA)                                                                         | `0e65a83`     |

### Runbook
- Start stack: `docker compose up -d` (run from `infra/`). Services: `mc_db`, `mc_cache`, `mc_backend`, `mc_frontend`.
- Backend tests: `.\backend\.venv\Scripts\python.exe -m pytest` (run from `backend/`; expect **64 passed**).
- Frontend build: `npm run build` (run from `frontend/`).
- Swagger UI: http://localhost:8000/api/docs/ · OpenAPI schema: http://localhost:8000/api/schema/ · Health: http://localhost:8000/api/health/
- App: http://localhost:5173 (login page) — Vite proxies `/api` and `/media` to the backend.
- Live QA smoke scripts (run from host): `.\scripts\qa_rbac_matrix.ps1` and `.\scripts\qa_integration_smoke.ps1` (PowerShell 5.1; they hit http://localhost:8000 directly and print a PASS/FAIL report).

### Known pitfalls (IMPORTANT for any continuation agent)
- **Vite stale-cache on Docker bind-mount:** after changing frontend code or env, the container may keep serving old transformed modules. Root cause of the AuthProvider crash and the `ERR_NAME_NOT_RESOLVED` login bug. **Fix: recreate the container** — `docker compose up -d --force-recreate frontend` (or at least `up -d`), NOT plain `docker compose restart`.
- **Proxy config:** browser must use the *relative* `/api` (so Vite proxies server-side). The server-side proxy target is `PROXY_TARGET=http://backend:8000/api` (compose). Do **not** set `VITE_API_BASE_URL` for dev — it bakes the Docker hostname into the client bundle.
- **PII encryption key:** `infra/.env` (gitignored) holds `PII_FIELD_KEY`. **Never change it** — existing encrypted patient rows in Postgres become unreadable. Keep the same key across environments. The key **was rotated on 2026-08-05** (it had been committed in `settings/test.py`); to rotate again use `python manage.py reencrypt_pii --old-key <OLD_KEY>` (backend container) after updating the env, then recreate the backend.
- **PowerShell 5.1** (Windows host): no `Invoke-WebRequest -SkipHttpErrorCheck`; use `curl.exe` and `Invoke-RestMethod`.

### Environment
- Windows host · Python 3.13.3 · Node 22.14.0 · Docker 29.6.1 + Compose v5.3.0 · git 2.45.1.
- Backend venv at `backend\.venv`; deps in `backend/requirements/{base,dev,prod}.txt`.
- Dev data: seed admin `admin` / `AdminPass123!`. Per-role test credentials: **`infra/TEST_USERS.md`** (all six roles verified logging in).

### QA subagent (opencode)
- Global agent file: `~/.config/opencode/agent/qa.md` (mode: subagent). Use it for independent QA runs, e.g. `subagent_type: "qa"`, prompt "run QA on the app". Requires an opencode restart to load (it was created after the last start).
- The agent is empowered to write/update automated tests but must NOT modify application code — it reports bugs for the main agent to fix.

### Security remediation pass (2026-08-05)
Driven by an independent security audit (subagent). Original Critical/High findings closed; verified live + by 33 new regression tests:
- **C-01** — real `DJANGO_SECRET_KEY` (in gitignored `.env`); `prod.py` now fails fast on placeholder/short keys, empty `ALLOWED_HOSTS`, or missing `PII_FIELD_KEY`.
- **H-01** — new `docker-compose.prod.yml` (gunicorn, `config.settings.prod`, `DJANGO_DEBUG=false`, built images, no bind mounts, Redis `requirepass`, loopback-only DB); `frontend/Dockerfile.prod` + hardened `nginx.conf` (CSP, HSTS, nosniff, X-Frame-Options, `/media/` served from a shared volume); `backend/.dockerignore` excludes `.env`.
- **H-02** — `POST /api/auth/logout/` blacklists the refresh token; frontend calls it on logout.
- **H-03** — center-scoped querysets + write-side checks: doctors restricted to their own appointments/schedules and cannot attach unapproved centers.
- **H-04** — PII masking now applies to IT, receptionist, and center_manager (full PII only for admin/doctor/nurse).
- **H-05 (partial)** — strict CSP + security headers at the prod edge; tokens still in `localStorage` (httpOnly-cookie migration is a known follow-up).
- **M-01** — `/api/schema/` + `/api/docs/` now require Admin/IT (anonymous 401).
- **M-03** — image uploads validate real image content (Pillow `verify`) and use randomized UUID filenames.
- **M-04** — dev compose binds PostgreSQL/Redis to `127.0.0.1`; prod Redis uses a password.
- **M-05** — PII decryption fails closed (never returns raw ciphertext); empty/None handled in the field converters.
- **N-1 (rotation)** — the Fernet PII key that had been committed in `settings/test.py` was rotated; `test.py` now generates an ephemeral key per run; `reencrypt_pii` management command re-encrypted 113 existing rows.
- **N-2** — doctor schedules validated like appointments (own profile + approved center only).
- **L-03** — `CORS_ALLOW_CREDENTIALS=False`; **I-03** — encrypted email removed from patient search.
- **Known remaining (accepted):** tokens in localStorage, unauthenticated `/media/` (UUID-obfuscated), Django admin exposes decrypted PII to `is_staff` (admin/IT), non-doctor roles see all centers (no user↔center model yet), prod TLS terminator not configured.

## Suggested Next Steps (prioritized)
1. **Security follow-ups (from the accepted-risk list):** move JWT refresh to an httpOnly `Secure` cookie flow (H-05); add an authenticated/signed-URL media endpoint (M-02); scope non-doctor staff reads by center (requires a user↔center model); add a TLS terminator to `docker-compose.prod.yml`.
2. **Activate CI:** push the three repos to GitHub (workflows in `infra/.github/workflows/` reference sibling repos `medicalconsultations-backend` / `medicalconsultations-frontend` under the same owner).
3. **Frontend test suite:** add vitest + React Testing Library (declared in decisions, still absent).
4. **Async layer:** add Celery on the existing Redis (appointment reminders/notifications, image processing).
5. **Doctor↔center approval UI:** surface the `DoctorCenterBinding` approve/pending flow in the frontend.
6. **Seed/demo data:** add a management command that loads sample centers, doctors, patients, medicines, appointments for a populated first run.
