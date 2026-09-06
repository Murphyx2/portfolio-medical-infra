# MedicalConsultations — Full Chronological Progress Log

> Archive. This is the complete, uncompressed session-by-session history that used to live inline
> in `PROGRESS.md`. It was split out on 2026-08-11 to keep `PROGRESS.md` cheap to read for routine
> work — `PROGRESS.md` now carries a condensed "Security Findings Ledger" (every finding code +
> one-line fix) plus the load-bearing pitfalls/invariants extracted from this log.
>
> Read this file only when you need the full story behind a specific past decision, commit, or bug
> — not as part of normal onboarding. `PROGRESS.md`'s "Current State" section is the authoritative
> day-to-day reference.

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

### 2026-08-10 — UX/accessibility critique + fix pass (`$impeccable critique`, frontend only)
Two rounds of an independent design critique (dual-agent: isolated design review + detector/evidence scan) against the frontend, with fixes applied between rounds. All work on frontend branch `ux/impeccable-critique-fixes`, merged `--no-ff` into `main` at `c8b64e8` (branch deleted post-merge). No backend/infra code changes. Verified throughout: `tsc -b && vite build` clean, **44 vitest** passing (was 36 at session start), live Docker stack.

**Round 1** (score 21/40 → fixed 1 P0 + 3 P1 + polish):
- `d67690b` — WCAG contrast: `--mc-primary` (`#66bb6a`→`#2e7d32`) and `--mc-muted` (`#5b7a99`→`#4f6f92`) were ~2.4:1/4.48:1 against white (need 4.5:1), now ~5.1:1/5.2:1. Also swapped the input-focus outline from `--mc-light` (too washed out, ~1.6:1) to `--mc-primary`.
- `51f9a4c` — `FormModal` (`ui.tsx`) gained `role="dialog"`/`aria-modal`/`aria-labelledby`, initial focus + focus-restore-on-close, Escape-to-close, and an internal submit-in-flight guard (disables Save/Cancel, swaps label to "Guardando…") — previously had none of this despite being reused by all 9 CRUD pages.
- `2515a50` — 8 of 9 forms (all but `Patients.tsx`) had **no try/catch on submit**, so a validation 400 threw unhandled and the modal just appeared to hang. Extracted `flattenError` (was duplicated in `Patients.tsx`) into `utils/errors.ts`, wired a `formError` state into every page's `FormModal` `error` prop. Also added `window.confirm` (naming the patient + appointment time) to `Appointments.tsx` `cancel()`/`complete()`, which previously fired with zero confirmation unlike every other destructive action in the app.
- `36eaf7c` — New `MaskedValue` component (inline SVG lock icon + `title` tooltip) for IT/CENTER_MANAGER-masked PII (`_mask()`-produced strings containing `•`), applied to `Patients.tsx`/`Doctors.tsx`. Previously masked values rendered as plain text indistinguishable from real data.
- `14486eb` — Dashboard's "recent appointments" stat was `appointments.length` capped at `page_size=5` (always showed "5"); replaced with a real count fetch, matching the existing patients/doctors-total pattern. Removed 2 dead i18n keys, wired the previously-unused `appointments.createdBy` key into an actual column, removed 2 detector-flagged `border-left` "slop" accents (`.stat-card`, `.log-entry`).

**Round 2 re-critique** (score 25/40 — fixes verified genuinely present, but found the pattern of stopping at the exact file first reported rather than the bug *class*, plus one regression):
- `baba3f7` — `MaskedValue`'s `aria-label` was overriding the element's own accessible name, so a screen reader heard only "Oculto para tu rol" and **never the masked value itself** — worse than before the fix existed. Dropped `aria-label`, added a `.sr-only`-prefixed label instead so both the value and the role explanation are announced.
- `a5533ad` — All 6 `remove()` (delete) handlers (Ars/Centers/Doctors/Medicines/Patients/Users) had the identical no-try/catch bug the round-1 submit fix targeted, just left open on the delete path. Same `flattenError` pattern, surfaced via `window.alert` since these aren't inside a `FormModal`.
- `53d16df` — `MaskedValue` had been applied to Patients/Doctors but missed `Records.tsx`, which shows the same masked `patient_info` fields and is reachable by every role including the masked ones.
- `0636ec2` — Extracted a shared `Dialog` primitive out of `FormModal` (backdrop/a11y/focus shell only, no submit/cancel button bar) and migrated `Records.tsx`'s hand-rolled detail modal (the busiest, most PHI-dense screen in the app — diagnosis, treatment, images, consultation logs) onto it, so it stopped drifting from `FormModal`'s a11y baseline. Also added a **Tab/Shift+Tab focus trap** to `Dialog` (new — `aria-modal="true"` was already being announced without one, so keyboard users could Tab out of a "modal" dialog into the sidebar behind it).
- `885a338` then `bc9ba02` — a real design lesson worth keeping: the round-1 polish pass added `position: sticky` to `.data-table th` for a sticky header. First diagnosis (`885a338`, switched `border-collapse: collapse`→`separate`) was wrong; the user reported the header was still broken (sitting over the first row). **Actual root cause:** `.data-table` has `overflow: hidden` (for its rounded corners), which per the CSS Overflow spec makes it a "scroll container" — so the sticky `<th>`'s `top` offset was computed relative to the *table's own box*, not the page, pushing it down onto row 1. `.table-scroll`'s `overflow-x: auto` wrapper has the identical problem (any non-`visible` overflow on *either* axis creates a scroll container per spec), so moving `overflow: hidden` off `.data-table` alone would not have fixed it. Properly fixing this needs the table to own a bounded, independently-scrolling box (its own `max-height` + `overflow-y: auto`) rather than tracking whole-page scroll — a real UX change, not a CSS one-liner. Reverted sticky positioning (`bc9ba02`) rather than take that on unprompted.

**Vite stale-cache recurrence:** mid-session, `curl` returning `200` on the dev server was (wrongly) treated as proof the container was serving current code. It wasn't — the bind-mounted Vite dev server had been silently serving code from *before the session's first commit* the entire time (same pitfall as the existing bullet below). Only caught because the user asked directly whether the containers had been recreated, which prompted diffing the actual served CSS against source. Fixed with `docker compose up -d --force-recreate frontend`, then re-verified by grepping the served files for source-only identifiers (e.g. `DIALOG_FOCUSABLE_SELECTOR`) rather than trusting HTTP status codes.

### 2026-08-11 — Patients column reorder, cédula required on create, Records i18n/picker fixes (backend `f2dfb3a`, frontend `d3ceb21`)
Branch `patients/cedula-required` both repos, merged `--no-ff`, branches deleted after.
- **Patients table** reordered to `full_name → age → gender → cedula → nss → phone → ars_name → ars_program_name → email → center_name` (cédula next to gender/NSS, correo next to centro). Form field order untouched (user-confirmed table-only scope).
- **Cédula required on patient creation only** — frontend `required={editId === null}`; backend `PatientSerializer.get_fields()` sets `cedula.required=True, allow_blank=False` only when `self.instance is None` (a plain check inside `validate_cedula` was tried first and found insufficient — DRF skips `validate_<field>` entirely when the field is omitted from the request and not marked `required`, so a POST with no `cedula` key at all slipped through; caught by hitting the live API directly, not by pytest, since test payloads always included the key). Backend tests updated: 2 replaced (`test_empty_cedula_still_allowed` → `_rejected_on_create` + `_still_allowed_on_update`), 3 payload-helper files given a default cédula.
- **Records.tsx bug fix** — headers were rendering literally as `COMMON.CEDULA`/`COMMON.NSS` because `t("common.cedula")`/`t("common.nss")` referenced i18n keys that don't exist (only `patients.cedula`/`patients.nss` do); fixed by pointing at the existing keys.
- **Record-creation patient picker** — sublabel changed from `cédula · NSS ...` to cédula only, per explicit request.
- Verified live against real Postgres (not just pytest): omitted-key and empty-string cédula both correctly 400 on create; PATCH-only-phone on an existing empty-cédula patient still 200s.

### 2026-08-11/12 — App-wide soft-delete conversion (backend `15215bf`, frontend `534580c`)
Branch `soft-delete/active-flag` both repos, 6 backend commits + 1 frontend commit, merged `--no-ff`, branches deleted after. Full design in the git history's commit messages (unusually detailed — read `git log -p` on the branch-tip commits if the summary below isn't enough) and condensed permanently into `PROGRESS.md`'s Behavioral Invariant 7 + two new Known Pitfalls entries, so this log entry stays a summary rather than repeating that detail.

**Scope:** every deletable model — Patient, DoctorProfile/DoctorSchedule, MedicalRecord/ConsultationLog/RecordImage, Appointment, MedicalCenter/DoctorCenterBinding, Medicine, ARS/ARSProgram, User — converted from hard delete to soft delete (`active`/`is_active` flag), invisible to everyone except admin, who restores explicitly.

**Design corrections caught during planning (before any code was written):** an independent plan-validation pass (which read Django/DRF source directly rather than relying on general knowledge) caught two bugs in the first-draft design — swapping `objects↔all_objects` wholesale on a ViewSet's queryset would have silently dropped `MedicalCenterViewSet`'s `doctor_count` `Count()` annotation for every admin request (not just inactive-row ones); and Django's own `/admin/` site would have silently hidden every deactivated row from the superuser too, since `ModelAdmin.get_queryset()` also uses the filtered default manager. A third gap (found via direct file read, not the review pass): `AuditModelAdmin.delete_model()` and Django admin's built-in bulk "Delete selected" action both still hard-deleted — both needed fixing so admin-panel access couldn't bypass the feature entirely.

**Real bug caught by the new tests, not by design review:** the `restore` action's `self.get_object()` went through the same active-only-by-default `get_queryset()` as everything else, which only widens on an explicit `?include_inactive=true` query param — but a plain `POST .../restore/` never sends that param, so restore 404'd on every inactive row regardless of permission. Fixed by having `get_queryset()` also widen whenever `self.action == "restore"` for a user who `can_view_inactive()`.

**Also fixed while auditing existing tests:** exactly one pre-existing test (`test_fix_m_01_07.py::test_nurse_can_delete_own_record`) was auditing the wrong thing post-conversion — it checked `.objects.filter(pk=X).exists()` is `False` after a delete, which still holds true under soft-delete (the filtered manager hides the row) but no longer means the row is actually gone. Strengthened to also assert `.all_objects.get(pk=X).active is False`. A full sweep (`grep -rn "\.delete(" backend/tests/`) found only 3 other `.delete(`-adjacent tests, all already correct for the corrected always-active-only-by-default design (not the "admin always sees everything" first draft, which would have broken the caching-invalidation test).

**Frontend:** 8 pages gained an admin-only "show inactive" checkbox + Activo/Inactivo badge + Restore button (`Table` gained a generic `onRestore`/`isInactive` prop pair). Records and Appointments had zero delete UI before this (Records' `Table` had no `onEdit`/`onDelete` at all; Appointments only had cancel/complete) — added at the top-level list only, not per-`ConsultationLog`/`RecordImage`, since those have no dedicated list UI and can't reveal inactive rows via the parent's toggle anyway (nested `prefetch_related` resolves through the child's own filtered manager, independent of the parent's `include_inactive` param — documented limitation, not fixed this pass).

**Live-verified against real Postgres** (not just pytest, not just the isolated test DB): full patient→record cascade; receptionist can't see inactive even with `include_inactive=true` forced in the URL; admin only widens with the param, not by default; restore doesn't cascade to the record; deleting a doctor profile 401s that user's login; restoring the profile leaves login blocked until the User is independently restored; Django admin's bulk delete is gone from the actions dropdown and `delete_model` soft-deletes. All QA-created test data cleaned up afterward. Backend test count: 210 → 224 (13 new in `tests/test_soft_delete.py`, plus the M-01-07 fix).

### 2026-08-12 — Impeccable design docs (PRODUCT.md/DESIGN.md), 3-page critique, P0 fix pass (backend `24737de`, frontend `258c393`)
Project-root work (`PRODUCT.md`, `DESIGN.md`, `.impeccable/`) via the `impeccable` skill, not in any of the 3 git repos — see PROGRESS.md's "Design-system artifacts" note. Code fixes on branch `fix/critique-p0-issues` both repos, merged `--no-ff`, branches deleted after.

**`$impeccable init`** produced `PRODUCT.md`: 6 roles, the deployed clinic's real name + logo as the confirmed branding (project root), Dominican-market positioning (cédula/NSS formats, SEMMA/SENASA ARS integration).

**`$impeccable document`** produced `DESIGN.md` (Scan mode, reverse-engineered from existing CSS/components) + `.impeccable/design.json` sidecar. North Star: "The Quiet Clinic." Palette: Clinical Green (`#2e7d32`)/Slate Blue text — **does not match the real deployed logo** (teal/orange/gold), flagged explicitly as out of `document`'s scope (would need a `new-work`/rebrand pass, not done this session). Companion 1-line fix: `es.json` nav label `"Panel"` → `"Dashboard"` (English term kept in Spanish UI, user-confirmed deliberate).

**`$impeccable critique`** — dual-agent (isolated design-review sub-agent + isolated detector/browser-evidence sub-agent) against Dashboard, Patients, Doctors. Browser automation (`claude-in-chrome`) unavailable all 3 runs — code-only evidence, disclosed each time, not treated as a failure. Scores: Dashboard 16/40, Patients 20/40, Doctors 20/40 (all "Acceptable, low end"). Full reports in `.impeccable/critique/2026-08-12T*.md`.

**Cross-cutting finding, not caught by any single page's review:** all three pages independently flagged the same underlying bug class — `window.confirm()`/`window.alert()` on every delete/restore action, breaking out of the app's own `Dialog` system at the exact moment a destructive action needs the most trust. User chose to fix this system-wide rather than per-page.

**P0 fixes (all 5, user-scoped to P0-only after a consolidated 4-question round):**
- `apps/appointments/views.py` — `filterset_fields` converted from a flat list to a dict form so `date_time` gained `gte`/`lt` lookups (previously only `exact`, useless for date-range queries). Dashboard's "Citas de hoy" was computed by slicing the 5 chronologically-**earliest** rows in the whole appointments table and filtering client-side for today's date — silently wrong on any dataset with real history (verified live: 87 real today+future rows existed, the old query would have shown ~0). Now queries `date_time__gte=<today 00:00>&date_time__lt=<tomorrow 00:00>` server-side and uses the response `count`, not `results.length`.
- `Dashboard.tsx` — the "next 5 appointments" fetch was already being made and thrown away every load; now rendered as an actual today's-schedule list (time, patient, doctor, status badge) instead of being discarded after deriving one (wrong) number from it.
- New `ConfirmDialog` component in `ui.tsx`, built on the existing `Dialog` shell. `Table`'s `onDelete`/`onRestore` props became `(row) => void | Promise<void>`; a new optional `getRowLabel` prop names the record in the confirm text. Table now owns confirm/cancel/error state internally — it awaits the handler, catches, and shows the error inline (styled `.form-error`) instead of the page catching and calling `window.alert`. New i18n keys `common.deleteConfirmNamed`/`restoreConfirmNamed` (`"¿Desactivar a {{name}}? Un administrador podrá restaurarlo más tarde."`) replace the old unnamed, reversibility-blind `deleteConfirm`/`restoreConfirm` text for every page using the shared `Table` (Ars/Centers/Doctors/Medicines/Patients/Records/Users — 7 pages). Each page's `remove()`/`restore()` simplified to just the API call + `load()`, letting errors propagate up to `Table` instead of catching locally. **`Appointments.tsx` intentionally not touched** — its cancel/complete/delete/restore are hand-rolled inside a table cell `render`, not routed through `Table`'s `onDelete`/`onRestore` props, and it wasn't one of the 3 critiqued pages; the same native-dialog pattern persists there as a known follow-up (not tracked in Suggested Next Steps yet — add if picked up).
- `apps/doctors/serializers.py::DoctorProfileSerializer.to_representation()` — masked-role viewers (non-admin/IT/self) got `contact_email = None`, visually identical to "doctor has no email," while `contact_phone`/`license_number` correctly used `_mask()` (`jo••••om`-style) right next to it in the same row. Changed to mask `contact_email` the same way. `bio` still nulls for masked roles (not flagged by the critique, left as-is). 2 backend test assertions updated (`test_fix_m_01_07.py`) to expect a masked string instead of `None`.

**Verified:** 224 backend / 44 frontend tests still pass (0 new tests — 2 modified assertions only), `tsc -b && vite build` clean, containers `--force-recreate`d and live-diffed (served `Dashboard.tsx`/`ui.tsx`/`Doctors.tsx`/`es.json` grepped for source-only strings, not just HTTP 200) before the user's own manual browser test, which passed. Live API check confirmed the appointments date filter: `?date_time__gte=<today>` returned `count: 87` against real seeded data (old query would've missed nearly all of them).

**Deferred, not forgotten (P1-P3 backlog across the 3 critique reports):** user picker missing name/sublabel + role filter (Doctors, Patients patient-picker precedent exists via `SearchableSelect` — not reused here); `DoctorSchedule`/`DoctorCenterBinding` still has no frontend surface at all (already tracked as Suggested Next Steps #3, independently confirmed by this critique); Dashboard shows identical content to all 6 roles (contradicts PRODUCT.md Product Principle 3); Patients form has no field grouping; several minor a11y gaps (`<th scope="col">`, row-action `aria-label`s naming the record). Full detail in the 3 `.impeccable/critique/*.md` snapshot files.
