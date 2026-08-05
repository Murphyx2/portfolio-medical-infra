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
- Initial commit per repo: infra `ef6f899`, backend `7641151`, frontend `19bb1d8`.

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

### 2026-08-05 — Step 4: Frontend MVP ✅
- Auth flow: login (JWT), token refresh, protected routes, role-aware navigation.
- Pages: Dashboard, Patients, Doctors, Centers, Medicines, Users (Admin/IT), Appointments (create + cancel/complete), Medical Records (create, detail, image upload, consultation logs).
- i18n EN default + ES (react-i18next), language switcher; palette theming across the app.
- API client with automatic token refresh and retry; multipart upload for record images.
- Verified: `npm run build` passes; Vite dev proxy (`/api`, `/media`) reaches backend container; login + `/api/auth/me` work through the proxy.
