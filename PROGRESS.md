# MedicalConsultations — Project Progress

> Living document: architecture reference + current-state snapshot. Read the whole thing before
> non-trivial backend changes — it carries security-audit history and design decisions that aren't
> otherwise visible in the code.
>
> Full session-by-session narrative (every commit, every bug story) was moved to
> **`PROGRESS_LOG.md`** on 2026-08-11 to keep this file cheap to read. Consult that file only when
> you need the story behind a specific past decision — everything load-bearing for day-to-day work
> is condensed into this file already.

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
|----------------------|-----------------------------------------------------------------------|
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

**Why PostgreSQL + Redis:** Postgres pairs best with Django's ORM (JSONB, full-text search, strong integrity for medical data); Redis is the cache and doubles as a future Celery broker. No better fit at this scale.

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

Every table above except `bindings`(=`DoctorCenterBinding`, which does have it too) also answers `POST .../<id>/restore/` and honors `?include_inactive=true` (admin-only, see Behavioral Invariant 7) — omitted from the table row-by-row to keep it scannable.

## Behavioral Invariants (do not regress)

1. **PII masking:** full patient PII (incl. names/birth-date/age) for ADMIN/DOCTOR/NURSE/RECEPTIONIST; **masked for IT and CENTER_MANAGER** (`first_name`/`last_name`/`full_name`/`birth_date`, `age=null`, plus contact/identifiers).
2. **Center scoping:** doctors see only centerless ("unbound") patients + their own centers' patients/records (or records they created); **doctor writes are rejected** for patients bound to foreign centers. Receptionists/nurses see all patients. Records/logs/images scope identically.
3. **IT boundary:** IT is never `is_staff`/`is_superuser`; only ADMIN can assign the ADMIN role, modify, or delete admin accounts.
4. **Media:** never served statically or by URL guessability — signed token required; no token = 404.
5. **Passwords:** Django `AUTH_PASSWORD_VALIDATORS` run on API user creation.
6. **Login throttling:** 10/min/IP — smoke scripts must wait ~70s between runs.
7. **Soft-delete, active-only visibility (2026-08-11):** Patient/DoctorProfile/DoctorSchedule/MedicalRecord/ConsultationLog/RecordImage/Appointment/MedicalCenter/DoctorCenterBinding/Medicine/ARS/ARSProgram/User are never hard-deleted — "delete" sets `active`/`is_active=False` (`apps/core/services.py::deactivate_with_cascade`, cascades only along `on_delete=CASCADE` FK edges, e.g. Patient→MedicalRecord→RecordImage; PROTECT/SET_NULL edges like Appointment.doctor are untouched). Default visibility is active-only for **everyone including admin**; admin widens with `?include_inactive=true`. `POST /<resource>/<id>/restore/` (admin-only) reactivates but never cascades to children. Deleting a `DoctorProfile` also sets its `User.is_active=False` (blocks login); restoring the profile does **not** restore the login — separate action. All of this funnels through one function, `apps/core/services.py::can_view_inactive()`, wrapped by `apps/core/permissions.py::CanViewInactive` — extending visibility to another role is a one-line change there, nothing else.

---

## Security Findings Ledger

Condensed history of every audit finding, grouped by pass. Codes are referenced by
`backend/tests/test_fix_*.py` filenames — don't delete those tests when refactoring the code
they guard. **Codes are only unique within their own audit** (each audit re-used C/H/M/L/N letters).
Full narrative for any item: `PROGRESS_LOG.md`.

**Audit #1** (2026-08-05) — backend `256c474` · frontend `523dbb2` · infra `d9cea85`
- C-01 real `DJANGO_SECRET_KEY`; prod fails fast on placeholder/missing secrets.
- H-01 `docker-compose.prod.yml` (gunicorn, no bind mounts, Redis `requirepass`) + hardened nginx (CSP/HSTS/etc).
- H-02 logout blacklists refresh token. · H-03 center-scoped querysets + write checks (doctors).
- H-04 PII masking for IT/receptionist/CM (receptionist access later restored, see Feature pass in log).
- H-05 (partial) CSP/security headers; tokens still in `localStorage` at this point (fixed 2026-08-06, see below).
- M-01 `/api/schema/`, `/api/docs/` → Admin/IT only. · M-03 image content validation (Pillow `verify`) + UUID filenames.
- M-04 dev compose binds DB/Redis to `127.0.0.1`; prod Redis password. · M-05 PII decrypt fails closed.
- N-1 rotated leaked test-only Fernet key; added `reencrypt_pii` command. · N-2 doctor schedules validated like appointments.
- L-03 `CORS_ALLOW_CREDENTIALS=False`. · I-03 encrypted email removed from patient search.

**Audit #2** (2026-08-05) — backend `25ddc94` · frontend `ef40919` · infra `5d4f5b8`
- H-01 bumped cryptography/Pillow (CVE fixes).
- H-02 token-guarded media (`ProtectedMediaView`, HMAC-signed token, 1h TTL, path-traversal guard).
- H-03 IT role boundary — IT force-stripped of `is_staff`/`is_superuser`; non-admin can't touch ADMIN accounts.
- M-01 password validators enforced on API user creation.
- M-02/M-03 patient nullable `center` FK (centerless = visible to all); doctor scoping + foreign-center write rejection.
- M-04 names/`birth_date` encrypted; plaintext `search_name` index added (migration split 0003/0004/0005, see Data Model note above).
- M-05 masking extended to first/last name, birth_date, age. · M-06 HTTPS-only prod (nginx redirect + self-signed `cert-init`).

**2026-08-06 UI/QA/Security batch** — backend `4156510` · frontend `a51c1ef` · infra `26b7d9f`
i18n of shared UI chrome; phone validation/formatting; email/birth_date input validation; masking extended to records/logs/appointments (F1); admin-flag demotion on role change (F2); search oracle closed for masked roles (F4); media guard hardened (F5); nginx `X-Forwarded-For` fix (F6); cryptography dep bump (D1). Deferred: react-router v8 (D3, needs React ≥ 19.2.7 — app is on React 18).

**2026-08-07 — M-01–M-07 + 3-day refresh** — backend `3aa27ee` · frontend `16a30a7`
- M-01 `cedula_last4`/`nss_last4` indexed columns replace full-table decrypt search (digit-search DoS fix); matching changed from "any substring" to "trailing digits only."
- M-02 nurse writes scoped to records they created. · M-03 doctor contact PII masked from non-admin/IT/self.
- M-04 media token URLs excluded from nginx access logs. · M-05 `NoStoreMiddleware` — no-store cache headers on all `/api/`, `/media/`.
- M-07 Django-admin writes audited via `AuditModelAdmin`. · H-03 refresh token lifetime shortened 7d → 3d.

**2026-08-06 — H-03 follow-through (httpOnly cookie)** — backend `012f2db` · frontend `0882194` · infra `cd7d9c5`
Refresh token moved out of `localStorage` into an httpOnly, `SameSite=Strict`, path-scoped (`/api/auth/`) cookie, rotated per refresh, cleared on logout. Access token stays in-memory only (`services/api.ts` module state).

**Deferred (recorded, no code changes; see log for full detail):** dev compose exposes `0.0.0.0` with `DEBUG=true` + default creds — bind to loopback before non-local exposure; `react-router-dom@7.18.2` sits in an advisory range but only affects RSC mode (app uses classic `BrowserRouter`) — hold until the React 19.2.7 upgrade; prod TLS cert is self-signed — mount real CA certs before public exposure.

---

## Current State (as of 2026-08-12)

Verified against the live stack (soft-delete pass, 2026-08-12: full manual QA against real Postgres — cascade, restore, doctor-login-lock, Django-admin parity — not just pytest). All three repos clean, all on `main`.

### Repos & latest commits
| Repo       | Path       | Latest commit |
|------------|------------|----------------|
| infra      | `infra/`   | `eac1b4a` |
| backend    | `backend/` | `24737de` (merge of `fix/critique-p0-issues`, tip `e79914e`) |
| frontend   | `frontend/`| `258c393` (merge of `fix/critique-p0-issues`, tip `ebb9e3d`) |

### Design-system artifacts (project root, not in any of the 3 git repos)
`PRODUCT.md`, `DESIGN.md`, `.impeccable/` (sidecar `design.json` + `critique/*.md` snapshots), and `LOGO ACTUAL.jpg` live at the repo-bundle root, **outside all three tracked repos** — the root itself isn't a git repo, so these are local-only unless separately backed up. Written/maintained via the `impeccable` skill (`$impeccable init`/`document`/`critique`). Current design system: "The Quiet Clinic" (Clinical Green + Slate Blue, system-ui only). Latest critique scores (2026-08-12, all "Acceptable, low end"): Dashboard 16/40, Patients 20/40, Doctors 20/40 — see `.impeccable/critique/` for full reports; their shared P0s (native `window.confirm`/`alert` instead of the app's own `Dialog`, Dashboard's broken today-count query, Doctors' `contact_email` masking) are fixed as of the commits above. Remaining P1-P3 backlog (user-picker sublabels, doctor schedule/center-binding UI, per-role dashboard content) is intentionally deferred, not forgotten.

### Runbook
- Start stack: `docker compose up -d` (from `infra/`). Services: `mc_db`, `mc_cache`, `mc_backend`, `mc_frontend`. **After pulling backend changes that add migrations, restart the backend container** — bind-mounted code hot-reloads, but `migrate` only runs at container startup.
- Backend tests: `pytest` (from `backend/`; last verified **224 passed**, 2026-08-12).
- Frontend build: `npm run build` (from `frontend/`). Frontend tests: `npm test` (last verified **44 passed**, 2026-08-12).
- Swagger UI: `http://localhost:8000/api/docs/` · Schema: `http://localhost:8000/api/schema/` · Health: `http://localhost:8000/api/health/`
- App: `http://localhost:5173` — Vite proxies `/api` and `/media` to the backend.
- Prod stack (gunicorn, built images, HTTPS-only): `docker compose -f docker-compose.prod.yml up -d` (self-signed cert auto-generated by `cert-init`; browser warns until real certs are mounted).
- Live QA smoke scripts (from host): `qa_full_verification.ps1`, `qa_integration_smoke.ps1`, `infra\scripts\qa_e2e_verification.py` — all green as of 2026-08-10. **Wait ~70s between runs** (login-throttle, see pitfalls below).

### Known pitfalls (read before touching related code)
- **Vite stale-cache on Docker bind-mount:** the frontend container can keep serving old transformed modules after code/env changes (root cause of 2+ past incidents, most recently 2026-08-10 where it silently served pre-session code through ~10 commits). Fix: `docker compose up -d --force-recreate frontend`, not plain `restart`. **Never trust an HTTP 200 as proof of freshness** — diff the actual served content (or grep for a source-only identifier) against current source. See [[feedback_verify_dont_assume_fixed]].
- **Proxy config:** browser must use the *relative* `/api` path. Server-side proxy target is `PROXY_TARGET=http://backend:8000/api`. Do **not** set `VITE_API_BASE_URL` for dev — it bakes the Docker hostname into the client bundle.
- **PII encryption key:** `infra/.env` (gitignored) holds `PII_FIELD_KEY`. **Never change it directly** — existing encrypted rows become unreadable. To rotate: `python manage.py reencrypt_pii --old-key <OLD_KEY>` then recreate the backend.
- **Login throttle race between smoke scripts:** 10/min/IP, and one script deliberately fires ~11 rapid logins. Wait ~70s between smoke-script runs or the next script's logins 429.
- **Postgres index vs. data migration:** encrypting existing rows and adding an index on the same table must be separate migrations (see Data Model note above) — Postgres rejects `CREATE INDEX` on a table with pending trigger events.
- **PowerShell 5.1 (Windows host):** no `Invoke-WebRequest -SkipHttpErrorCheck`; use `curl.exe`/`Invoke-RestMethod`. Multipart uploads: `curl.exe -F` (no `Invoke-RestMethod -Form` in 5.1).
- **Server-side caching + tests:** `CachedListViewMixin` (medicines/ARS/centers) and `CachedSpectacularAPIView` (schema) use the real Django cache, which pytest-django's per-test rollback does **not** reset. `tests/conftest.py`'s autouse `clear_cache` fixture handles this — if a new cached endpoint shows flaky counts in unrelated tests, check this fixture first.
- **Postgres-only migrations:** trigram GIN indexes (`patients/migrations/0008`, `records/migrations/0003`) are `RunPython` ops gated on `schema_editor.connection.vendor` — do **not** add a `GinIndex` directly to `Meta.indexes`, it breaks `migrate` on the SQLite test backend.
- **Cache invalidation is signal-based, not `AuditMixin`-based:** several admins (`MedicalCenterAdmin`, `MedicineAdmin`, `ARSAdmin`, etc.) write through a separate `AuditModelAdmin` base, not the DRF `AuditMixin`. An `AuditMixin`-only invalidation hook would miss every Django-admin edit. Use `post_save`/`post_delete` signals (`apps/core/signals.py`).
- **Encrypted-column sort is a paired backend/frontend change (2026-08-10 perf pass):** `cedula`/`nss`/`phone`/`email`/`age` were removed from backend `ordering_fields` (can't sort encrypted columns in SQL); the frontend compensates with a client-side, current-page-only sort for exactly those 5 columns (`Patients.tsx`). Don't revert one side without the other.
- **Custom sub-agent personas don't register natively** in this harness — see "Sub-agent personas" below.
- **`SoftDeleteManager` makes `objects` the filtered default manager** on the 12 soft-deletable models (`apps/core/models.py`) — any ViewSet's class-level `queryset` must use `Model.all_objects`, not `Model.objects`, or admin's `include_inactive=true` has nothing to widen (`MedicalCenterViewSet`'s `doctor_count` `Count()` annotation must survive this swap too — don't drop the `.annotate()`/`.select_related()` chain when editing). Forward FK access (`appointment.doctor`) stays unfiltered via `_base_manager` — don't set `Meta.base_manager_name` on these models, that's what keeps it that way. Django admin needed its own fix too (`AuditModelAdmin.get_queryset`/`delete_model`/`get_actions` in `apps/core/admin.py`) — it isn't covered by the DRF-side changes.
- **Nested prefetches don't honor `include_inactive`:** `MedicalRecordViewSet`'s `prefetch_related("images")` and `ARSViewSet`'s `prefetch_related("programs")` resolve through the *child* model's own filtered manager regardless of the parent's `include_inactive` param — an admin viewing a record with `?include_inactive=true` still won't see a deactivated `RecordImage` nested inside it. Query `RecordImageViewSet`/programs directly instead. Known limitation, not a bug.

### Sub-agent personas
- Persona briefs (mission, checklist, report format) live in `infra/AGENTS.md`: **security** (severity-categorized audit findings, requires approval before fixing) and **qa** (pytest/vitest, RBAC matrix, PII masking, JWT rotation, throttling, E2E — may add tests, must not touch app code).
- This harness does **not** register custom `.claude/agents/*.md` files as callable `subagent_type`s (confirmed even for official plugin agents). Dispatch instead via `subagent_type: "general-purpose"` with the persona brief from `infra/AGENTS.md` pasted into the prompt. See [[harness_custom_agents_unsupported]].

### Environment
- Windows host · Python 3.13.3 · Node 22.14.0 · Docker 29.6.1 + Compose v5.3.0 · git 2.45.1.
- Backend venv at `backend\.venv`; deps in `backend/requirements/{base,dev,prod}.txt`.
- Dev data: seed admin `admin` / `AdminPass123!`. Per-role test credentials: `infra/TEST_USERS.md` (all six roles verified).

### Accepted risks (current)
- Non-doctor staff roles (receptionist/nurse/IT/CM) still see all centers (no user↔center visibility model for those roles).
- Django admin still exposes decrypted PII to the single `is_staff` admin account (IT revoked; only ADMIN has it).
- Prod TLS uses a self-signed cert (real certs must be mounted before public exposure).
- Patient edit form shows raw stored digits for cédula when reopening an existing patient (cosmetic).
- `react-router` stays on v7 (needs React ≥ 19.2.7 first; app is on React 18).
- Records detail shows raw SOAP section initials (cosmetic).
- `db_reviewer` read-only Postgres credential lives in `TEST_USERS.md` — low urgency (repos private, port loopback-bound) but flagged for rotation.

### Information-handling summary
- **Not in the repos:** the real `.env` (secrets, `PII_FIELD_KEY`, DB/Redis passwords) is gitignored everywhere and absent from git history. Without `PII_FIELD_KEY`, encrypted rows are unreadable even with full DB access.
- **Public by design:** the three repos contain all source, migrations, tests, CI, compose — anyone with them can rebuild the app from `.env.example` + a fresh key. Unavoidable; the code is the product.
- **Dev credentials are exposed** in `TEST_USERS.md`/QA scripts — local-dev only, stack binds to loopback so they grant nothing unless a dev stack is exposed on a real IP.
- **Operational rule:** `.env` is the only secret store. If these repos ever go to a public remote, treat all documented dev credentials as compromised and never commit `.env`.

## Suggested Next Steps (prioritized)
1. **Non-doctor center scoping:** extend the patient `center` model decision to receptionists/nurses/center-managers.
2. **Async layer:** add Celery on the existing Redis (appointment reminders, image processing) — give it its own DB index, since DB 0 already does throttling + reference-list/schema caching.
3. **Doctor↔center approval UI:** surface the `DoctorCenterBinding` approve/pending flow in the frontend.
4. **Seed/demo data:** management command loading sample centers/doctors/patients/medicines/appointments.
5. **Rotate `db_reviewer` password** (low urgency, see accepted risks).
6. Consider trigram indexes for Medicine/ARS `search_fields` if those lists grow large (both already cached, so this is a `search=` latency concern only).
7. **Sticky table headers (deferred):** needs `.data-table` to own its own bounded `max-height` + `overflow-y: auto` instead of tracking whole-page scroll — a real UX decision, not a CSS one-liner. See `PROGRESS_LOG.md` 2026-08-10 entry for why the naive fix doesn't work.
8. **`theme/palette.ts` is dead code** with stale colors (pre-contrast-fix `#66BB6A`) — delete, or sync to `index.css`'s current tokens if a JS-side color source is ever needed.
9. CI workflows in `infra/.github/workflows/` may reference stale repo names — verify against `Murphyx2/MedicalConsultation-{backend,frontend,infra}`.
10. **Soft-delete follow-ups (deferred, 2026-08-11 pass):** no restore UI yet for `ConsultationLog`/`RecordImage` (no dedicated list view exists) or `DoctorSchedule`/`DoctorCenterBinding` (API supports restore, frontend doesn't surface it) — low priority since the nested-prefetch limitation (Known Pitfalls) already blocks seeing inactive children of a record/ARS from the parent view anyway.
