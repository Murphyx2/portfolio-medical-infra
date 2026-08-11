# MedicalConsultations — Project Progress

> Living document: original specification, design decisions, and a running log of progress.
> Read **Current State** (near the end) for the authoritative snapshot; the **Progress Log** above it is chronological history.

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
- **IT** — system maintenance, infrastructure (**no Django admin** — revoked in audit #2)
- **Nurse** — supports patient care (assists with records/logs)
- **Center Manager** — manages a specific medical center's operations

## Core Modules

1. **Doctors** — full name, contact information, specialty, license, optional presence
   schedule per center. A doctor is bound to **zero or more** medical centers.
2. **Patients** — address, contact information, optional email, medical records
   (doctor-written), optional images, current treatment / medicine / doses, a
   consultation log per visit, plus insurance fields (`cedula` 11-digit, `nss`,
   `ars`/`ars_program`) and a nullable `center` FK (**centerless = unbound = visible
   to all staff**; center-bound patients are scoped to that center's doctors).
   Names/birth-date encrypted at rest with a plaintext lowercase `search_name` index
   for search.
3. **Medicines** — generic (medical) term, commercial name, concentration.
4. **Appointments** — created by a doctor or a receptionist for a patient.

## Data Model (entities & design intent)

Backend models live under `backend/apps/` (one folder per app, each with models/serializers/views/urls/tests). Key entities and the non-obvious decisions a continuation model must preserve:

| Entity | App | Notes / design intent |
|--------|-----|----------------------|
| `User` | accounts | Custom user; `role` ∈ {ADMIN, DOCTOR, RECEPTIONIST, IT, NURSE, CENTER_MANAGER}. **Only ADMIN has `is_staff`/`is_superuser`**; IT is force-revoked in `save()` (audit #2, H-03). |
| `MedicalCenter` | centers | name, code, address, phone, email. |
| `DoctorCenterBinding` | centers | Doctor↔center with `approved` (admin-approves); drives doctor scoping. |
| `DoctorProfile` / `DoctorSchedule` | doctors | Profile (specialty, license, contacts) + optional per-center presence schedule. |
| `Patient` | patients | PII encrypted at rest: `first_name`/`last_name`/`birth_date`/`phone`/`address`/`email`/`cedula`/`nss` (all `EncryptedCharField`); **plaintext lowercase `search_name`** (indexed) keeps name search working; `gender`; `ars`/`ars_program` FKs; **nullable `center` FK — `NULL` = unbound = visible to all staff**, non-null = scoped to that center's doctors. |
| `MedicalRecord` | records | per-patient clinical record; `patient`, `created_by`, `center`, diagnosis/treatment/notes; `images` relation. |
| `ConsultationLog` | records | per-visit SOAP log; `patient`, `doctor`, `center`. |
| `RecordImage` | records | attachment to a record; ≤ 5 MB, magic-byte verified (Pillow `verify`), randomized UUID filenames, served only via signed token. |
| `ARS` / `ARSProgram` | ars | Insurer + programs; seeded SEMMA (`SM`) and SENASA (`SE`). |
| `Medicine` | medicines | generic term, commercial name, concentration. |
| `Appointment` | appointments | `patient`, `doctor`, `center`, `date_time`, `duration_minutes`, `status`, `created_by`. |

**Migration split (audit #2, M-04):** `patients` 0003 (schema) / 0004 (`encrypt_patient_names` data backfill) / 0005 (`search_name` index) are separate transactions on purpose — Postgres rejects `CREATE INDEX` on a table with pending trigger events from prior `ALTER`/`UPDATE` in the same migration. Preserve this split when adding encrypted columns + backfills.

## Technology Decisions

| Concern              | Decision                                                            |
|----------------------|---------------------------------------------------------------------|
| Backend              | Python + Django (LTS) + Django REST Framework                        |
| Frontend             | React + Vite + TypeScript (SPA)                                     |
| Database             | PostgreSQL 16                                                       |
| Cache / message      | Redis 7 (cache; later Celery broker)                                |
| Auth                 | JWT tokens (djangorestframework-simplejwt)                          |
| API language         | **Spanish default** + English (i18n, react-i18next)                 |
| Architecture         | Modular monolith now, microservice-ready                            |
| Deployment           | Docker Compose on a laptop, portable to CI/CD                       |
| Tests                | pytest (backend), vitest + React Testing Library (frontend)         |
| Security             | RBAC, field-level PII encryption, audit log, rate limiting, token-guarded media, HTTPS |

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
`accounts, ars, centers, doctors, patients, records, medicines, appointments`.

## API Surface

All routes are under `/api/` (backend `config/urls.py` + per-app `urls.py`; full schema at `/api/schema/`, Swagger at `/api/docs/` — both Admin/IT only). JWT via `Authorization: Bearer <access>`. Throttled endpoints (incl. login, 10/min/IP).

| Endpoint | Methods | Permission gating |
|----------|---------|-------------------|
| `/api/auth/login/` | POST | public (throttled) |
| `/api/auth/logout/` | POST | authenticated (blacklists refresh token) |
| `/api/auth/token/refresh/` | POST | valid refresh token |
| `/api/auth/me/` | GET | authenticated |
| `/api/auth/users/` | CRUD | ADMIN (write); ADMIN/IT (read); non-admin cannot create/promote/delete ADMIN (audit #2 H-03) |
| `/api/patients/` | CRUD | staff; `?search=` on `search_name`, filters `gender`/`ars`/`center`; doctors scoped to centerless + own-center; IT/CM get masked output |
| `/api/medical-records/` | CRUD | staff read; write ADMIN/DOCTOR/NURSE; doctors scoped by center/creator |
| `/api/consultation-logs/` | CRUD | staff read; write ADMIN/DOCTOR/NURSE; doctors scoped by center/doctor |
| `/api/images/` | CRUD | staff read; write ADMIN/DOCTOR/NURSE (valid image ≤ 5 MB); doctors scoped by record center |
| `/api/centers/` | CRUD | staff read; write ADMIN/IT |
| `/api/bindings/` | CRUD | staff read; write/approve ADMIN only |
| `/api/ars/` | CRUD | staff read; write ADMIN/RECEPTIONIST |
| `/api/medicines/` | CRUD | staff |
| `/api/appointments/` | CRUD | staff; doctors scoped to own schedules/approved centers |
| `/api/schema/`, `/api/docs/` | GET | ADMIN/IT (audit #1 M-01) |
| `/api/health/` | GET | public |
| `/media/<path>?token=…` | GET | signed token only (1h, HMAC); 404 without/with bad token; path-traversal guarded (audit #2 H-02) |

## Behavioral Invariants (do not regress)

1. **PII masking:** full patient PII (incl. names/birth-date/age) for ADMIN/DOCTOR/NURSE/RECEPTIONIST; **masked for IT and CENTER_MANAGER** (`first_name`/`last_name`/`full_name`/`birth_date`, `age=null`, plus contact/identifiers).
2. **Center scoping:** doctors see only centerless ("unbound") patients + their own centers' patients/records (or records they created); **doctor writes are rejected** for patients bound to foreign centers. Receptionists/nurses see all patients. Records/logs/images scope identically.
3. **IT boundary:** IT is never `is_staff`/`is_superuser`; only ADMIN can assign the ADMIN role, modify, or delete admin accounts.
4. **Media:** never served statically or by URL guessability — signed token required; no token = 404.
5. **Passwords:** Django `AUTH_PASSWORD_VALIDATORS` run on API user creation.
6. **Login throttling:** 10/min/IP — smoke scripts must wait ~70s between runs.

---

## Progress Log (chronological)

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
- Redaction (initial): IT sees masked patient PII; receptionist/IT see masked clinical record content. *(Later changed — see Feature pass.)*
- `create_admin` management command for reproducible setup.
- Tests: 31 passed (auth, roles, CRUD, permission matrix, encryption-at-rest, redaction).
- Verified end-to-end via live stack: login → center → doctor → patient → medicine → appointment → record → consultation log; PII ciphertext confirmed in Postgres.
- Commits: backend `40f0f5a` (MVP), `51bc6a4` (token blacklist + image validation), `3f76b4f` (admin image upload); infra `0325a37` (PII key env template).

### 2026-08-05 — Step 4: Frontend MVP ✅
- Auth flow: login (JWT), token refresh, protected routes, role-aware navigation.
- Pages: Dashboard, Patients, Doctors, Centers, Medicines, Users (Admin/IT), Appointments (create + cancel/complete), Medical Records (create, detail, image upload, consultation logs).
- i18n EN default + ES (react-i18next), language switcher; palette theming across the app. *(Default later flipped to Spanish — see Feature pass.)*
- API client with automatic token refresh and retry; multipart upload for record images.
- Verified: `npm run build` passes; Vite dev proxy (`/api`, `/media`) reaches backend container; login + `/api/auth/me` work through the proxy.
- Commits: frontend `ae7e889` (MVP), `33c93a3` (rotate-refresh persistence); infra `4263b7b` (compose frontend env + progress).

### 2026-08-05 — Step 5: Security review + CI/CD ✅
- JWT token blacklist enabled (rotation blacklists old refresh tokens); frontend persists rotated refresh tokens.
- Record image upload validation (size ≤ 5 MB, image extensions only); Admin allowed to upload.
- Django `check --deploy` passes (only warning from intentionally short test key).
- GitHub Actions in infra: `backend-ci.yml` (checks + pytest), `frontend-ci.yml` (type-check + build).
- Full README quick-start for fresh clone of the 3 repos.
- Verified: clean `docker compose down/up` boots all 4 services; image upload → `/media/...` serves 200; record lists the image. *(Media later made token-guarded — see audit #2.)*
- Hotfix: frontend `AuthProvider` was never mounted → Login page crashed; wrapped app in `AuthProvider` in `main.tsx`.
- Added Swagger/OpenAPI via `drf-spectacular`: `/api/docs/` (Swagger UI) + `/api/schema/` (29 paths, JWT auth) — public at the time, later gated to Admin/IT (see audit #1).
- Fixed login `ERR_NAME_NOT_RESOLVED`: dev browser now uses relative `/api` via Vite proxy; proxy target moved to server-side `PROXY_TARGET` env (`http://backend:8000/api`), `VITE_API_BASE_URL` no longer baked into the client bundle.
- Added `TEST_USERS.md` with a working account per role (admin, doctor, receptionist, nurse, it, cm) — all verified logging in.
- Commits: infra `8b3e453` (CI + README), `49ef3d9` (progress finalize), `9301d30` (AuthProvider/Swagger notes), `407445f` (PROXY_TARGET + TEST_USERS), `37931ae` (handoff docs); backend `5445a85` (Swagger/OpenAPI); frontend `b4610b0` (AuthProvider), `0e65a83` (proxy fix).

### 2026-08-05 — Milestone: MVP complete ✅
All 5 steps done. Backend (Django) 31 tests passing at this point; frontend builds; stack runs via Docker Compose with PostgreSQL + Redis cache; patient PII encrypted at rest; RBAC + audit + throttling in place; CI/CD ready to activate on push. *(Test count is now 118 — see Current State.)*

### 2026-08-05 — Security audit #1 (original security pass)
> Note: finding codes here (C-01, H-01…H-05, M-01/M-03…M-05, N-1/N-2, L-03, I-03) are **independent** of audit #2's codes — each audit used its own numbering.
Driven by an independent security audit (subagent). Original Critical/High findings closed; verified live + by 33 new regression tests. Commits: backend `256c474`, frontend `523dbb2`, infra `d9cea85`.
- **C-01** — real `DJANGO_SECRET_KEY` (in gitignored `.env`); `prod.py` now fails fast on placeholder/short keys, empty `ALLOWED_HOSTS`, or missing `PII_FIELD_KEY`.
- **H-01** — new `docker-compose.prod.yml` (gunicorn, `config.settings.prod`, `DJANGO_DEBUG=false`, built images, no bind mounts, Redis `requirepass`, loopback-only DB); `frontend/Dockerfile.prod` + hardened `nginx.conf` (CSP, HSTS, nosniff, X-Frame-Options, `/media/` served from a shared volume — later replaced by token-guarded proxy, see audit #2); `backend/.dockerignore` excludes `.env`.
- **H-02** — `POST /api/auth/logout/` blacklists the refresh token; frontend calls it on logout.
- **H-03** — center-scoped querysets + write-side checks: doctors restricted to their own appointments/schedules and cannot attach unapproved centers.
- **H-04** — PII masking applied to IT, receptionist, and center_manager (full PII only for admin/doctor/nurse). *(Later relaxed for receptionist — see Feature pass.)*
- **H-05 (partial)** — strict CSP + security headers at the prod edge; tokens still in `localStorage` (httpOnly-cookie migration is a follow-up).
- **M-01** — `/api/schema/` + `/api/docs/` now require Admin/IT (anonymous 401).
- **M-03** — image uploads validate real image content (Pillow `verify`) and use randomized UUID filenames.
- **M-04** — dev compose binds PostgreSQL/Redis to `127.0.0.1`; prod Redis uses a password.
- **M-05** — PII decryption fails closed (never returns raw ciphertext); empty/None handled in the field converters.
- **N-1 (rotation)** — the Fernet PII key that had been committed in `settings/test.py` was rotated; `test.py` now generates an ephemeral key per run; `reencrypt_pii` management command re-encrypted 113 existing rows.
- **N-2** — doctor schedules validated like appointments (own profile + approved center only).
- **L-03** — `CORS_ALLOW_CREDENTIALS=False`; **I-03** — encrypted email removed from patient search.

### 2026-08-05 — Feature pass
Spanish-default i18n, ARS/insurance domain, receptionist PII access, and audit completion (verified: **90 pytest passed** at this point, frontend builds, all three live smoke scripts green). Commits: backend `3cf47ee`, frontend `6de4183`, infra `777e233`.
- **Default language Spanish** — frontend defaults to `es` (persisted via `localStorage("mc_lang")`); backend `LANGUAGE_CODE = "es"` (DRF/SimpleJWT/admin messages now Spanish — tests assert on `code`/status, not English text).
- **ARS domain** — new `backend/apps/ars`: `ARS` (unique `ars_id`, name) + `ARSProgram` (name, unique per ARS); seeded via data migration: **SEMMA** (`SM`, program "P Y P SEMMA") and **SENASA** (`SE`, program "SENASA Contigo"). API `api/ars/` (read: any staff; write: ADMIN/RECEPTIONIST only) with writable nested `programs` (0..n, reconciled on save). Frontend `/ars` page (ADMIN/RECEPTIONIST) with inline program editor.
- **Patient insurance fields** — patients gain `cedula` (`000-0000000-0` format, encrypted), `nss` (digits only, encrypted), `ars` FK, `ars_program` FK (validated to belong to the patient's ARS). All optional. Frontend patient form + columns updated.
- **Receptionist PII** — receptionists now see/edit full patient PII (phone/address/email/cedula/nss). Masking (redacted `••`) applies only to **IT** and **CENTER_MANAGER** (extended to names/birth-date in audit #2). Existing masking tests + `qa_rbac_matrix.ps1` + `qa_full_verification.ps1` updated to match.
- **Audit completion** — `AuditLog.Action` now declares `LOGOUT`; `UserViewSet` audits user CRUD; CREATE audit restored for medical records / consultation logs / record images / appointments (their `perform_create` overrides had bypassed `AuditMixin`); `AuditLog` registered in Django admin (read-only).
- **QA fixes** — program `id` made writable in `ARSSerializer` (PATCH reconcile no longer 500s); fixed `Test-Masking` counting bug in `qa_rbac_matrix.ps1` (function emitted two pipeline outputs so the check was always truthy).

### 2026-08-05 — QA + cedula + modal-guard pass
Independent QA agent run + regression fixes (verified: **118 pytest passed**, frontend builds, **6 vitest passed**, live cedula checks 12/12). Commits: backend `0eda59d`, frontend `b74e49c`, `5840710`, infra `5d4f5b8` (QA cedula script).
- **QA agent report** — 100 pytest at run start; RBAC matrix 58/58, PII masking, JWT rotation + blacklist, login throttle 429 at attempt 11, E2E smoke all green; vitest 5/6 then 6/6 after the BUG-1 fix.
- **Cedula digits-only** — backend `0eda59d`: `validate_cedula` strips non-digits and enforces exactly 11; `CEDULA_RE` removed. Frontend `b74e49c`: submit normalizes, columns format, `inputMode="numeric"` + `maxLength={13}`. Live-verified (`010-0108492-0` → stored `01001084920`; 10-digit → 400; IT/CM masked).
- **Modal drag-release guard (QA BUG-1)** — frontend `b74e49c` (shared `FormModal`) + `5840710` (Records detail modal): backdrop `onPointerDown` records press origin; `.modal` `onPointerDown` clears the flag + `stopPropagation()`; backdrop closes only when the press actually started on it. Fixes stale-flag close after pointerup-outside/pointercancel.
- **Regression tests** — `backend/tests/test_cedula_digits_only.py`, `frontend/src/components/ui.test.tsx` + vitest config/setup, `infra/scripts/qa_cedula_verification.ps1`.
- **Accepted (cosmetic, BUG-2)** — patient edit form shows raw stored digits (not formatted) when reopening an existing patient.

### 2026-08-05 — Security audit #2 (HIGH/MEDIUM fixes)
> Note: finding codes here (H-01…H-03, M-01…M-06) are **independent** of audit #1's codes above — each audit used its own numbering.
Independent security audit → **0 CRITICAL / 3 HIGH / 6 MEDIUM**, all addressed and committed (backend `25ddc94`, frontend `ef40919`, infra `5d4f5b8`). Live-verified: `/media/` 404 without token + 200 with signed token, IT-create-ADMIN → 400, weak password → 400, IT/CM masked names, doctor foreign-center record → 400.
- **H-01 deps** — `cryptography>=48.0.1,<49.0` (was 43; GHSA-537c-gmf6-5ccf etc.) and `Pillow>=12.3.0,<13.0` (CVE-2026-59199 heap OOB) in `requirements/base.txt`.
- **H-02 token-guarded media** — new `ProtectedMediaView` (`records/views.py`) serving `MEDIA_URL` only to holders of a short-lived HMAC-signed token (`sign_media_token`/`verify_media_token` in `core/services.py`, 1h `MEDIA_TOKEN_MAX_AGE`); `get_image_url` appends `?token=…`; `config/urls.py` routes `media/<path>` (removed DEBUG `static()`); prod nginx now proxies `/media/` to the backend instead of serving the volume directly.
- **H-03 IT role boundary** — `accounts/models.py` save(): ADMIN keeps staff+superuser, IT forced `is_staff=False, is_superuser=False` (migration `0002_revoke_it_staff` flips existing IT); `_guard_role_assignment` (non-admin cannot assign ADMIN role or modify admin accounts); destroy of an ADMIN by non-admin → 403. Defeats IT using Django admin to read decrypted PII.
- **M-01 password policy** — `validate_password` (AUTH_PASSWORD_VALIDATORS) runs on API user creation.
- **M-02/M-03 patient center scoping** — patients gain nullable `center` FK (**centerless = unbound = visible to all staff**, so fixtures/tests/smoke scripts stay valid); doctors see centerless OR own-center patients (+ records in own centers); doctor writes (records/logs/images) rejected for patients bound to foreign centers (`_validate_patient_scope` + RecordImage record-scope check); receptionists/nurses see all patients; doctor-created records default to their center. Frontend patient form + table gained a center selector (`Patients.tsx`, i18n keys, `center`/`center_name` in types).
- **M-04 names/birth-date encryption** — `first_name`/`last_name` → `EncryptedCharField()`, `birth_date` → `EncryptedCharField(null=True, blank=True)`; **accepted tradeoff:** plaintext lowercase `search_name` (201) column + index keeps name search working (`?search=`, `filterset_fields` on `search_name`). Migrations split **0003** schema / **0004** `encrypt_patient_names` data (raw-SQL encryption of existing rows, `is_encrypted` guard) / **0005** search_name index — separate transactions because Postgres rejects `CREATE INDEX` on a table with pending trigger events from prior ALTER/UPDATE.
- **M-05 masking extended** — `PatientSerializer.to_representation` now also masks `first_name`/`last_name`/`full_name`/`birth_date` and nulls `age` for IT/CM.
- **M-06 HTTPS-only prod** — `nginx.conf`: port 80 → 301 to HTTPS, `listen 443 ssl` (TLS1.2/1.3, HSTS); `docker-compose.prod.yml`: `cert-init` service auto-generates a self-signed cert into a `certs` volume, frontend mounts it read-only, ports `443:443` + `80:80`, `DJANGO_SECURE_SSL_REDIRECT=true`.
- **Also** — `SearchFilter` added to `PatientViewSet` (name search now actually queryable); `RecordImageViewSet` ordered to silence the DRF unordered-list warning; `/media/` path-traversal guard in `ProtectedMediaView`.

### 2026-08-06 — UI feature batch + QA/Security audit #3 follow-ups
Five frontend feature requests + all findings from independent QA and security audit runs (verified: **144 pytest passed**, frontend builds, **15 vitest passed**, live E2E smoke green). Commits: backend `4156510`, frontend `a51c1ef`, infra `26b7d9f`.
- **i18n of shared chrome** — `ui.tsx`/`guards.tsx` use `useTranslation` for every action label (`common.actions/edit/delete/cancel/close/view/noData/loading/deleteConfirm/phoneInvalid`; new keys added to both `es.json` and `en.json`).
- **Phone formatting + validation** — new `src/utils/phone.ts` (+10 vitest): stored digits-only, displayed `(809) 555-1212`, format-as-you-type on Patients/Centers/Doctors forms (`type="tel"`); backend `core/validators.py` `validate_phone` (exactly 10 digits, NFKC-normalized, letters rejected) wired into patient/center/doctor serializers; empty-required-phone guard in Centers/Doctors forms (QA BUG-3). Live: `(809) 555-1212` → stored `8095551212`.
- **Patient form layout** — cédula field moved below last name (cosmetic request).
- **Records page** — patient name is now a clickable row link that opens the record detail for all staff (replaces the old `onEdit`-based action); detail header shows `Records · patient name` with the record title in a subtitle.
- **Backend input validation (QA BUG-1/BUG-2)** — `PatientSerializer.validate_email` (Django email validator) + `validate_birth_date` (isoformat, not in future). Live: bad email → 400.
- **F1 masking extended** — `is_masked_role()` (IT/CM only) now also applied in `MedicalRecordSerializer`, `ConsultationLogSerializer`, `AppointmentSerializer` (full_name, doctor/created_by names, notes). Live: IT sees `Li***ck` / `se***te`.
- **F2 admin demotion** — `User.save()` clears `is_staff`/`is_superuser` for all non-ADMIN roles (migration `0003_flags_from_role` applied to the live stack).
- **F4 search oracle** — masked roles get `search_fields=[]` + `filterset_fields=["gender","ars","center"]` only (name-search oracle closed). Live: IT `?search=` returns the full list.
- **F5 media guard** — `ProtectedMediaView` uses `is_relative_to(media_root)` instead of a manual prefix check.
- **F6 nginx** — `/api/` and `/media/` proxies overwrite `X-Forwarded-For` (`$remote_addr`) rather than appending.
- **D1 deps** — `cryptography>=49.0.0,<51.0` (50.0.0 installed in venv; CVE fix).
- **Deferred: D3 react-router v8** — requires React ≥ 19.2.7, the app is on React 18; not upgraded (documented accepted risk).

### 2026-08-06 — Patient-create fix + NSS validation
Adding a patient with admin appeared impossible because backend validation 400s were silently swallowed by the frontend. Fixed + NSS hardening (backend `aa99fbe`, frontend `21dda54`):
- **Error surfacing** — `FormModal` gained an `error` prop (alert banner); `Patients.tsx` catches API errors and flattens DRF field messages (e.g. `nss: NSS must contain digits only.`) instead of failing silently.
- **NSS frontend** — `inputMode="numeric"`, `maxLength={11}`, strips non-digits as you type.
- **NSS backend** — `validate_nss` NFKC-normalizes fullwidth digits, rejects letters/symbols/non-ASCII, enforces max 11 digits (previously accepted 12-digit and fullwidth values).
- Verified: **146 pytest**, **16 vitest**, build clean; live: 12-digit → 400, fullwidth → stored ASCII, letters → 400.

### 2026-08-06 — Pagination (backend + frontend) + read-only DB access
New patients created via the form were invisible on the Patients page because the backend never honored `?page_size` and the frontend had no pagination UI. Fixed (backend `defadef`, frontend `5be9ae3`, infra `9a65c71`):
- **Root cause** — `PageNumberPagination` with no `page_size_query_param` silently ignored the frontend's `?page_size=100`, so every list endpoint returned 20 rows and the frontend rendered only page 1 (patients sorted by `search_name` beyond row 20 were hidden).
- **Backend** — new `apps/core/pagination.py::DefaultPagination` (`page_size=20`, `page_size_query_param="page_size"`, `max_page_size=200`); wired as `DEFAULT_PAGINATION_CLASS`.
- **Frontend** — new `Pagination` component in `ui.tsx` (numbered pages + prev/next + "Página X de Y · N registros", ellipsis collapse, returns null when a single page) rendered **above and below** the table on all 7 list pages: Patients, Centers, Doctors, Medicines, Appointments, Records, Users.
- **DB access** — read-only PostgreSQL role `db_reviewer` (SELECT only; writes denied) documented in `TEST_USERS.md`; PII stays Fernet-encrypted at rest.
- **QA agent** — no application-code bugs; live 37/37 checks green (pagination, NSS, RBAC, masking, JWT rotation/blacklist, throttling 429 on 11th login). New **`infra/scripts/qa_live_verification.ps1`** supersedes the stale 8-digit-phone smoke scripts.
- Verified: **150 pytest**, **21 vitest**, build clean; live `?page_size=100` → 100 results, page 2 → remainder.

### 2026-08-06 — Per-page size selector + wider content area (frontend `12ba590`, `f997165`)
- **Page-size selector** — the shared `Pagination` control now always shows a `select` (default **50**, then 75/100; i18n "Elementos por página"). Changing it resets to page 1; nav + info line only render when multiple pages. Wired into all 7 list pages (Patients, Centers, Doctors, Medicines, Appointments, Records, Users) via `pageSize` state + `onPageSizeChange`. Backend `DefaultPagination` unchanged (still defaults to 20; frontend always sends `page_size`, `max_page_size=200` covers 100).
- **Content width** — `.content` `max-width` widened 1200px → 1600px to reduce the Patients table's horizontal scroll.
- Verified: **23 vitest**, build clean, frontend container recreated, HTTP 200.

### 2026-08-06 — Sidebar layout + server-side search & sorting + Records revamp (backend `8a55385`, frontend `84d824c`)
- **Layout** — nav moved into a fixed 230px dark **left sidebar** (brand + vertical nav); a right-aligned light **topbar** holds the language switcher, user chip, role badge and logout; responsive below 900px.
- **Server-side search** — every list page shows a top `SearchBar`; the query is debounced 300ms and sent as `?search=` only from the **4th character**. Implemented with DRF `SearchFilter` on all 7 list endpoints (patients, centers, doctors, medicines, appointments, records, users).
- **Encrypted PII search** — patients and records also match **decrypted cedula/NSS**: digit-containing terms are OR-matched against Fernet-decrypted values (`PatientSearchFilter` / `RecordSearchFilter`), keeping pagination `count` correct. Masked roles (IT/CM) keep the F4 restrictions (patients unfiltered; records title-only).
- **Sortable columns** — clicking a column header cycles **asc → desc → clear**; the backend uses `?ordering=` (`-` prefix for desc). Patients' encrypted columns (phone/email/cedula/nss/age) are sorted in Python on the `list` endpoint; records' cedula/NSS columns are display-only (not sortable). ARS and Dashboard are not list pages and are excluded.
- **Shared frontend state** — new `hooks/useListControls.ts` (pagination, page-size, debounced search, sort cycle, query builder) wired into all 7 pages; Appointments and Records keep their previous default orderings (`date_time` asc, `date` desc).
- **Records revamp** — columns reordered to **Full Patient Name · Cédula · NSS · Title · Date · Doctor**; name/cédula/NSS cells are clickable and open the expediente (existing detail modal); the list search matches patient name, record title and cedula/NSS. The create form uses a **searchable patient picker** (matches name/cedula/NSS, shows formatted cédula + NSS sublabel); the record title **auto-fills with the patient's name + current date** and re-fills every time the patient changes.
- Verified: **174 pytest**, **32 vitest**, build clean, frontend container recreated, HTTP 200; live `?search=<cedula>` finds the patient, center `?ordering=doctor_count` works, and record `patient_info` exposes cedula/nss (masked for IT/CM).

### 2026-08-06 — Search UX (3 chars, Enter, background) + formatted-cedula search fix (backend `4442f43`, frontend `5b69c01`)
- **3-char minimum** — list search (and the Records patient picker) now activates from the **3rd** character (was 4). Placeholder/hint strings updated in both locales.
- **Enter triggers immediately** — pressing Enter in the search bar bypasses the debounce and runs the search right away; otherwise the 300ms stop-typing debounce applies.
- **Background loading** — `useListControls` now exposes `initialLoading` + `runList(fetcher)`: the previous in-flight request is **aborted** (an `AbortSignal` is passed to `api.get`), so stale responses can't overwrite newer results, and the full-page spinner only shows on the very first load — re-searching, sorting and page changes keep the current table visible while the new page loads. Applied to all 7 list pages.
- **Formatted-cedula search fix** — `_patient_ids_matching_digits` (patients + records) now strips non-digits from the query before matching the decrypted cedula/NSS, so copying the displayed `001-1234567-8` into the search bar finds the patient/records (the UI formats cedula, so the raw match previously returned 0 and looked like a phantom patient).
- Verified: **176 pytest**, **33 vitest**, build clean, frontend container recreated, HTTP 200; live `?search=001-1234567-8` → 4 patients and 13 records.

### 2026-08-06 — Single-flight token refresh (frontend `c9cfa4d`)
- **Bug** — after the 15-minute access token expired, the next interaction fired several concurrent requests (list + dropdown fetches like `/api/centers/?page_size=100`). Every one 401'd and each called `tryRefresh()` with the **same single-use refresh token** (`ROTATE_REFRESH_TOKENS` + `BLACKLIST_AFTER_ROTATION`); only the first rotation succeeded, the others got 401 → `clearTokens()` → visible 401s and forced logout.
- **Fix** — `services/api.ts` `tryRefresh()` is now **single-flight**: a module-level promise is shared by all concurrent 401 handlers, so the refresh endpoint is hit exactly once, the token rotates once, and every waiting request retries with the new access token. `clearTokens()` only runs on a genuine refresh failure.
- Verified: **35 vitest** (+2 new `services/api.test.ts`), build clean, frontend container recreated, HTTP 200.

### 2026-08-07 — Security audit fixes M-01–M-07 + 3-day refresh token (backend `3aa27ee`, frontend `16a30a7`)
- **M-01 (digit-search DoS)** — `Patient` gains plaintext `cedula_last4`/`nss_last4` index columns, populated in `save()` and backfilled by migration `0007`. Digit search now matches **in SQL on the trailing digits** (`patient_ids_matching_digits` in `core/services.py`) instead of decrypting every row in Python. Matching changed from "any substring of the full number" to "trailing digits": full/formatted numbers (`001-1234567-8`) and last-4 searches still work; prefix/middle-substring searches no longer match (2 tests updated to trailing forms).
- **M-02 (nurse write-scoping)** — `CanManageRecords.has_object_permission`: nurses may update/destroy only records **they created** (owner resolved across `created_by`/`uploaded_by`/`doctor`); doctors keep center scoping; admins unrestricted. Record creation stays open to nurses.
- **M-03 (doctor contact PII)** — `DoctorProfileSerializer` masks `license_number`/`contact_phone` and nulls `contact_email`/`bio` for everyone except admin/IT/the doctor themself. Frontend needed no change (`formatPhone` passes `•`-values through, `Table` renders null as empty, only ADMIN/IT can edit).
- **M-04 (media tokens in logs)** — nginx `/media/` location now `access_log off;` so the signed `?token=` never reaches access logs.
- **M-05 (cache headers)** — new `apps/core/middleware.NoStoreMiddleware` sets `Cache-Control: private, no-store, max-age=0` + `Pragma: no-cache` on all `/api/` and `/media/` responses (verified live).
- **M-07 (admin audit trail)** — `AuditModelAdmin` base (mirrors the DRF `AuditMixin`) logs every admin add/change/delete to `AuditLog`; all app ModelAdmins inherit it (incl. `CustomUserAdmin(AuditModelAdmin, UserAdmin)`).
- **H-03 (shorten refresh window)** — `JWT_REFRESH_LIFETIME_DAYS` default and `infra/.env` set to **3** days (was 7); verified live (refresh `exp` = 3 days).
- Verified: **197 pytest** (176 + 19 new M-fix tests + 1 last-4 index test; 2 search tests updated), **35 vitest**, build clean, backend recreated (migrations `0006`/`0007` applied incl. data backfill), frontend HTTP 200.

### 2026-08-06 — H-03 follow-through: httpOnly refresh-token cookie (backend `012f2db`, frontend `0882194`, infra `cd7d9c5`)
> Backfilled into this log — the code/commits predate this entry; PROGRESS.md itself was never updated at the time.
- **Cookie-based refresh** — the SPA no longer holds the refresh token in `localStorage` (closes the "H-03 residual" item below). The access token stays **in memory only** (`services/api.ts` module state); the refresh token travels in an httpOnly, `SameSite=Strict`, path-scoped (`/api/auth/`) cookie set by the backend (`REFRESH_COOKIE_*` settings in `config/settings/base.py`), rotated on every `/api/auth/token/refresh/` call and cleared on logout.
- **Backend** — login/refresh responses set/rotate the cookie server-side instead of returning the refresh token in the JSON body; logout blacklists the current refresh token and clears the cookie.
- **Frontend** — `tryRefresh()` (single-flight, from the 2026-08-06 fix above) now calls `/api/auth/token/refresh/` with `credentials: "include"` and no request body; `setAccessToken`/`getAccessToken` are the only client-side token state.
- **QA scripts** — all `infra/scripts/qa_*` updated to drive the cookie-based flow (session-based `Invoke-WebRequest`/`requests.Session` instead of reading a refresh token out of the JSON body) plus pagination-safe doctor lookups and login-throttle retry handling.
- Verified live: httpOnly cookie set on login, rotates on refresh, reused-old-cookie → 401 (blacklisted), cleared on logout.

### Deferred — production hardening (recorded, no code changes)
- **H-01** — dev compose publishes `0.0.0.0:8000/5173` with `DEBUG=true` and known default credentials (`admin/AdminPass123!`, role accounts `Pass123!x`). Bind to loopback + rotate creds before any non-local exposure.
- **M-06** — `react-router-dom@7.18.2` is in the GHSA-qwww-vcr4-c8h2 range, but the advisory only affects RSC mode and the app uses classic `BrowserRouter`; keep on v7 until the React ≥ 19.2.7 upgrade (see accepted risks).
- **M-08** — prod compose ships a self-signed TLS cert together with `SECURE_HSTS_PRELOAD`; mount real CA certs before any public exposure.
- **H-02 (reassessed, lower severity)** — the "committed PII key" was a **test-fixture key** in `settings/test.py` (pytest in-memory SQLite only); no persistent data was ever encrypted with it, so **no `reencrypt_pii` run is needed**. Optional git-history purge if the repo ever goes public.

### 2026-08-10 — Performance pass: query optimization + Redis reference-list/schema caching + frontend list UX (backend `824410f` merged `30a8c50`, frontend `29d2def` merged `f1cbd35`)
Worked on two branches (`backend: perf/caching-and-query-opts`, `frontend: perf/list-ux-improvements`), merged into `main` after unit tests + a full live-stack QA run. No infra changes.

**Backend — query/perf fixes:**
- `PatientViewSet`: `select_related("ars","ars_program","center")` (the serializer's `ars_name`/`ars_program_name`/`center_name` fields were causing N+1 queries); doctor center-scoping rewritten from a `.distinct()` + join to an `Exists()` subquery (no row multiplication, no `.distinct()` needed).
- `patient_ids_matching_digits` (`apps/core/services.py`) now returns a lazy queryset (`values_list("id", flat=True)`) instead of a materialized Python list, so `id__in=patient_ids_matching_digits(term)` in `PatientSearchFilter`/`RecordSearchFilter` compiles to a single SQL subquery.
- Encrypted-field orderings (`cedula`/`nss`/`phone`/`email`/`age`) are no longer sorted in Python on the backend — they were removed from `ordering_fields`, so DRF's `OrderingFilter` just ignores an `?ordering=` request for them and falls back to default ordering. **The frontend now sorts those 5 columns client-side** (see below) — this is a paired backend/frontend change, don't revert one side without the other.
- New indexes: `MedicalRecord.date` / `ConsultationLog.date` (both default-order `-date` on every list; plain btree, both DB backends) — `records` migrations `0002`/`0003`. Postgres-only trigram GIN indexes on `Patient.search_name` and `MedicalRecord.title` (used with `__icontains` by the search filters) — `patients` migration `0008`, `records` migration `0003`; both are `RunPython` guarded on `schema_editor.connection.vendor != "postgresql"` (no-op on the SQLite test backend) and **deliberately not mirrored in `Meta.indexes`** (a `GinIndex` in `Meta.indexes` would break `migrate` on SQLite — schema editors don't skip index types they don't support, they just fail). Live-verified applying cleanly against real Postgres (`CREATE EXTENSION pg_trgm` + `CREATE INDEX ... USING gin`).
- `CONN_MAX_AGE=60`, `GZipMiddleware`, Redis `KEY_PREFIX` + 1s socket timeouts (`config/settings/base.py`).

**Backend — caching (design note for future continuation):** the original plan was to invalidate the cache from the DRF-only `AuditMixin` hook; **rejected during design review** because `MedicalCenterAdmin`/`MedicineAdmin`/`ARSAdmin`/`ARSProgramAdmin`/`DoctorCenterBindingAdmin` all use a *separate* `AuditModelAdmin` base (`apps/core/admin.py`) for Django-admin writes — an AuditMixin-only hook would leave the cache stale after any admin-panel edit. Built as `post_save`/`post_delete` signals instead (fires regardless of write path). Keep this in mind if refactoring cache invalidation again.
- `apps/core/caching.py::CachedListViewMixin` — caches `list()` responses (Redis, 300s TTL, version-counter invalidation) for `MedicineViewSet`/`ARSViewSet`/`MedicalCenterViewSet`. Verified auth-agnostic (no per-role query scoping) before applying — do **not** apply this mixin to a viewset whose `get_queryset()` varies by user/role (e.g. `DoctorCenterBindingViewSet`, `PatientViewSet`) without re-checking that invariant.
- `apps/core/signals.py::connect_cache_invalidation()` (wired from `CoreConfig.ready()`) — `post_save`/`post_delete` on `Medicine`/`ARS`/`ARSProgram`/`MedicalCenter`/`DoctorCenterBinding` bump the relevant Redis version counter.
- `apps/core/views.py::CachedSpectacularAPIView` — caches the `/api/schema/` response (1h TTL) **inside `get()`**, not by wrapping the URL with Django's `cache_page`. This matters: `cache_page` around the whole view would intercept the request *before* DRF's `dispatch()` runs `check_permissions()`, so a cached admin response could leak to a non-admin/IT caller. Caching inside `get()` means the lookup only ever runs after `SERVE_PERMISSIONS` (`IsAdminOrIT`) has already passed. Live-verified: warming the cache as admin, then requesting as `doctor` still gets 403.
- `tests/conftest.py` gained an autouse `cache.clear()` fixture — LocMemCache (the test cache backend) is **not** reset by pytest-django's per-test transaction rollback, so without this, caching state leaks across tests (surfaced as flaky/wrong row counts in unrelated tests that hit `/api/medicines/`, `/api/ars/`, `/api/centers/`).
- New `tests/test_caching.py` (10 tests) + 2 new query-count regression tests in `tests/test_patients.py` (`CaptureQueriesContext`-based, assert query count doesn't scale with row count / doesn't duplicate rows).

**Frontend:**
- Records/Appointments/Doctors/Users: the combined `useEffect(() => { load(); api.get(dropdownData)... }, [load])` was refetching the dropdown/picker data (patients/doctors/centers/users/roles) on **every** page/sort/search change, since `load` is a `useCallback` that changes identity on those. Split into `useEffect(load, [load])` + a separate `useEffect(..., [])` that fetches the picker data once on mount. (`Patients.tsx` already had this split — a good reference for the shape.)
- `Records.tsx::openDetail` — the record detail fetch and the consultation-logs fetch are independent (`await` then fire-and-forget), so they were running sequentially; parallelized with `Promise.all`. Record images get `loading="lazy"`.
- `Patients.tsx` — client-side sort added for the 5 columns the backend no longer sorts (`phone`/`email`/`cedula`/`nss`/`age`): a local `clientSort` state + `handleColumnSort` wrapper that intercepts those 5 keys before they'd reach `useListControls`'s server-driven `handleSort` (which would otherwise send an inert `?ordering=` and reset to page 1 for nothing). Sorts only the **currently-loaded page** — this is a client-side per-page sort, not a full-dataset sort.
- `Appointments.tsx` — patient picker changed from a `<select>` that preloaded 100 patients to the existing `SearchableSelect` component (same pattern `Records.tsx`'s record form already used).
- Verified: **210 pytest** (backend), **36 vitest** (frontend), `tsc -b && vite build` clean, and a full live-stack QA run (`qa_e2e_verification.py` 175/175, `qa_integration_smoke.ps1` clean, `qa_full_verification.ps1` 92/92) after restarting the backend/frontend containers (bind-mounted, so `docker compose restart` was enough to pick up the code — but the 3 new migrations only apply at container **startup**, so a restart was required to actually run them against the live Postgres, not just a hot-reload).

---

## Current State (2026-08-10)

Everything below was verified against the live stack. All three repos are clean (`git status` empty), all on `main` (the two perf branches were merged with `--no-ff` and can be deleted).

### Repos & latest commits
| Repo       | Path                                                                                            | Latest commit |
|------------|-------------------------------------------------------------------------------------------------|---------------|
| infra      | `infra/` (compose, env, docs, CI, scripts)                                                      | `fdc7c80`     |
| backend    | `backend/` (Django API)                                                                         | `30a8c50` (merge of `perf/caching-and-query-opts`, tip `824410f`) |
| frontend   | `frontend/` (React SPA)                                                                         | `f1cbd35` (merge of `perf/list-ux-improvements`, tip `29d2def`) |

### Runbook
- Start stack: `docker compose up -d` (run from `infra/`). Services: `mc_db`, `mc_cache`, `mc_backend`, `mc_frontend`. **After pulling backend changes that add migrations, restart the backend container** (`docker compose restart backend`) — bind-mounted code hot-reloads, but `migrate` only runs at container startup, so new migrations won't apply to the live Postgres until you do.
- Backend tests: `.\backend\.venv\Scripts\python.exe -m pytest` (run from `backend/`; expect **210 passed**).
- Frontend build: `npm run build` (run from `frontend/`).
- Frontend tests: `npm test` (vitest + RTL; expect **36 passed**).
- Swagger UI: http://localhost:8000/api/docs/ · OpenAPI schema: http://localhost:8000/api/schema/ · Health: http://localhost:8000/api/health/
- App: http://localhost:5173 (login page) — Vite proxies `/api` and `/media` to the backend.
- Prod stack (gunicorn, built images, HTTPS-only): `docker compose -f docker-compose.prod.yml up -d` (self-signed cert auto-generated by the `cert-init` service; browser will warn until real certs are mounted).
- Live QA smoke scripts (run from host): `qa_full_verification.ps1` (92/92), `qa_integration_smoke.ps1`, and `backend\.venv\Scripts\python.exe infra\scripts\qa_e2e_verification.py` (175/175) were re-run against this state on 2026-08-10 and are green (`qa_rbac_matrix.ps1`, `qa_cedula_verification.ps1`, `qa_live_verification.ps1` were **not** re-run this pass — assume current but unverified). **Wait ~70s between runs** (see login-throttle pitfall below) — running them back-to-back in the same minute produces false failures from 429s, not real bugs.

### Known pitfalls (IMPORTANT for any continuation agent)
- **Vite stale-cache on Docker bind-mount:** after changing frontend code or env, the container may keep serving old transformed modules. Root cause of the AuthProvider crash and the `ERR_NAME_NOT_RESOLVED` login bug. **Fix: recreate the container** — `docker compose up -d --force-recreate frontend` (or at least `up -d`), NOT plain `docker compose restart`.
- **Proxy config:** browser must use the *relative* `/api` (so Vite proxies server-side). The server-side proxy target is `PROXY_TARGET=http://backend:8000/api` (compose). Do **not** set `VITE_API_BASE_URL` for dev — it bakes the Docker hostname into the client bundle.
- **PII encryption key:** `infra/.env` (gitignored) holds `PII_FIELD_KEY`. **Never change it** — existing encrypted patient rows in Postgres become unreadable. Keep the same key across environments. The key **was rotated on 2026-08-05**; that old key only ever lived in the pytest `settings/test.py` (in-memory SQLite), so no persistent data was encrypted with it and no `reencrypt_pii` pass is required (H-02 reassessed). To rotate the current key, run `python manage.py reencrypt_pii --old-key <OLD_KEY>` (backend container) after updating the env, then recreate the backend.
- **Login throttle race between smoke scripts:** the `login` throttle is 10/min per IP, and `qa_full_verification.ps1` deliberately fires ~11 rapid logins. Running the smoke scripts back-to-back within the same minute causes the next script's role logins to be 429-throttled (failures look like empty tokens / "bad_authorization_header"). **Wait ~70s between smoke script runs.**
- **Postgres index vs. data migration:** encrypting existing rows (`patients 0004`) must run in a separate migration transaction from the `search_name` index (`0005`) — Postgres rejects `CREATE INDEX` on a table with pending trigger events. Keep this split if adding columns + backfills.
- **PowerShell 5.1** (Windows host): no `Invoke-WebRequest -SkipHttpErrorCheck`; use `curl.exe` and `Invoke-RestMethod`. For multipart uploads use `curl.exe -F` (no `Invoke-RestMethod -Form` in 5.1).
- **Server-side caching + tests:** `apps/core/caching.py::CachedListViewMixin` (medicines/ARS/centers) and `CachedSpectacularAPIView` (schema) use the real Django cache (LocMemCache in tests), which pytest-django's per-test transaction rollback does **not** reset. `tests/conftest.py` has an autouse `clear_cache` fixture for this — if you add a new cached endpoint and see flaky/wrong counts in unrelated tests, this is almost certainly why (check the fixture is still running, not that it's a real bug).
- **Postgres-only migrations:** the trigram GIN indexes (`patients/migrations/0008`, `records/migrations/0003`) are `RunPython` operations that check `schema_editor.connection.vendor` and no-op on SQLite — do **not** add a `GinIndex` directly to a model's `Meta.indexes`, it will break `migrate` on the SQLite test backend (the schema editor doesn't skip unsupported index types, it just emits invalid SQL for them).
- **Cache invalidation must be signal-based, not `AuditMixin`-based:** `MedicalCenterAdmin`/`MedicineAdmin`/`ARSAdmin`/`ARSProgramAdmin`/`DoctorCenterBindingAdmin` write through `AuditModelAdmin` (Django admin), a *different* class from the DRF `AuditMixin` used by the API viewsets. Hooking cache invalidation into `AuditMixin` alone would silently miss every Django-admin edit. Use `post_save`/`post_delete` signals (`apps/core/signals.py`) for anything that needs to react to writes regardless of path.

### Environment
- Windows host · Python 3.13.3 · Node 22.14.0 · Docker 29.6.1 + Compose v5.3.0 · git 2.45.1.
- Backend venv at `backend\.venv`; deps in `backend/requirements/{base,dev,prod}.txt`.
- Dev data: seed admin `admin` / `AdminPass123!`. Per-role test credentials: **`infra/TEST_USERS.md`** (all six roles verified logging in).

### Subagents (opencode)
- Global agent files under `~/.config/opencode/agent/`:
  - **`qa.md`** (mode: subagent) — independent QA runs, e.g. `subagent_type: "qa"`, prompt "run QA on the app". May write/update automated tests but must NOT modify application code — reports bugs for the main agent to fix.
  - **`security.md`** (mode: subagent) — independent security audits. New subagents need an opencode **restart** to load.

### Accepted risks (current, 2026-08-10)
- ~~JWT tokens in `localStorage`~~ — resolved 2026-08-06 (H-03 httpOnly cookie migration, see Progress Log).
- Non-doctor staff roles (receptionist/nurse/IT/CM) still see all centers (no user↔center visibility model for those roles).
- Django admin still exposes decrypted PII to the single `is_staff` admin account (IT revoked; only ADMIN has it).
- Prod TLS uses a self-signed cert (real certs must be mounted before public exposure).
- Patient edit form shows raw stored digits for cédula when reopening (cosmetic, BUG-2).
- `react-router` stays on v7 (D3 deferral) — v8 needs React ≥ 19.2.7; app is on React 18. Upgrade React as a separate task before bumping.
- Records detail shows raw SOAP section initials (cosmetic; a "skip section" helper could hide them).

### Risk assessment / information handling (verified 2026-08-05)
What someone obtaining this document **and/or** the repos can and cannot do:

- **Not in the repos (secrets):** the real `.env` (DJANGO_SECRET_KEY, PII_FIELD_KEY, POSTGRES_PASSWORD, REDIS_PASSWORD) is **never committed** — gitignored in `infra/` and `backend/`, excluded via `backend/.dockerignore`, and absent from git history (verified). `PII_FIELD_KEY` is required to decrypt patient data; without it, encrypted-at-rest rows are unreadable even with full DB access.
- **Public by design (repos = full project):** the three repos contain all source code, migrations, tests, CI, and compose files. Anyone with them can rebuild and run the entire application from scratch using `.env.example` + a freshly generated key. This is unavoidable — the code is the product.
- **Dev credentials are exposed:** `admin`/`AdminPass123!` and role accounts (`Pass123!x`) live in `TEST_USERS.md` and the QA scripts. They are local-dev only — the stack binds to `127.0.0.1`/localhost, so they grant nothing unless a dev stack is reachable on a real IP.
- **Security blueprint is visible:** the document describes the encryption scheme, masking rules, token-guarded media, endpoints, and exact finding numbers. Useful for targeting, but exploitation still requires real secrets (`.env`) or DB access; it does not by itself expose patient data.
- **Operational rule:** `.env` is the only secret store. If these repos are ever pushed to a public remote, treat all documented dev credentials as compromised, keep ports loopback-bound, and never commit `.env`.

## Suggested Next Steps (prioritized)
1. ~~Activate CI~~ — done: the three repos are pushed to GitHub (`Murphyx2/MedicalConsultation-{backend,frontend,infra}`, all **private**). The `medicalconsultations-*` repo names referenced in `infra/.github/workflows/` may need updating to match if CI hasn't been re-verified against the new remote names/owner.
2. **Non-doctor center scoping:** extend the patient `center` model decision to receptionists/nurses/center-managers (visible-center model for those roles).
3. **Async layer:** add Celery on the existing Redis (appointment reminders/notifications, image processing) — note the cache DB (`redis://.../0`) is now also doing reference-list/schema caching (2026-08-10), not just throttling; give Celery its own DB index if added.
4. **Doctor↔center approval UI:** surface the `DoctorCenterBinding` approve/pending flow in the frontend.
5. **Seed/demo data:** add a management command that loads sample centers, doctors, patients, medicines, appointments for a populated first run.
6. **Follow-ups from the 2026-08-10 perf pass:** rotate the `db_reviewer` Postgres password documented in `TEST_USERS.md` (flagged during a repo-privacy review — low urgency since the repos are private and the port is loopback-bound, but it's a live credential in a tracked file); consider whether Medicine/ARS `search_fields` (also `icontains`-based) would benefit from the same trigram-index treatment as `Patient.search_name`/`MedicalRecord.title` if those lists grow large enough to matter (both are already cached, so this is a `search=` latency concern, not a list-load one).
