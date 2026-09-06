# MedicalConsultations Infrastructure

Orchestration, environment templates, documentation, and CI/CD for the
MedicalConsultations project — a role-based medical consultations management
system (patients, doctors, centers, records with images, medicines, appointments).

**This is a scoped-down demo branch** of a larger production system —
insurance/pricing, visit tracking, patient communications, prescriptions, and
reporting are real, working parts of the full product, just not included
here. See `backend/README.md` for the full list.

## Repositories

| Repo     | Contents                                    |
|----------|---------------------------------------------|
| `infra`  | (this repo) compose, env templates, docs, CI/CD |
| `backend`| Django REST API (`medicalconsultations-backend`) |
| `frontend`| React + Vite SPA (`medicalconsultations-frontend`) |

## Prerequisites

- Docker + Docker Compose (Docker Desktop on Windows/Mac, docker engine on Linux)

## Quick start

```bash
# 1. Clone the three repos side by side
git clone <url>/medicalconsultations-infra infra
git clone <url>/medicalconsultations-backend backend
git clone <url>/medicalconsultations-frontend frontend

# 2. Configure environment
cd infra
cp .env.example .env
#   - set DJANGO_SECRET_KEY and POSTGRES_PASSWORD to random values
#   - set PII_FIELD_KEY (generate one, see .env.example)
#   - ensure PII_FIELD_KEY is the SAME across restarts so encrypted data stays readable

# 3. Start the stack
docker compose up -d --build

# 4. Create the initial admin user
docker compose exec backend python manage.py create_admin \
  --username admin --email admin@example.com --password "ChangeMe123!"

# 5. Seed synthetic demo data (patients, records)
docker compose exec backend python manage.py seed_demo_data --confirm
```

Then open:
- Frontend SPA: http://localhost:5173
- API root / browsable: http://localhost:8000/api/
- Django admin: http://localhost:8000/admin/

## Stack

- **Backend**: Python 3.13, Django 5.2 (LTS), Django REST Framework, SimpleJWT
- **Database**: PostgreSQL 16 (`db`)
- **Cache**: Redis 7 (`cache`)
- **Frontend**: React + Vite + TypeScript, i18n (EN/ES)
- **Security**: JWT auth, role-based permissions, Fernet field-level PII encryption,
  audit log, DRF throttling, hardened prod settings

See `docs/architecture.md` for the full design and the monolith → microservices
transition map. Track progress in `PROGRESS.md`.

## CI/CD (GitHub Actions)

Workflows in `.github/workflows/`:
- `backend-ci.yml` — Django system checks + pytest for the backend repo
- `frontend-ci.yml` — `npm run build` (type-check + bundle) for the frontend repo

Push the three repos to the same GitHub owner; the workflows auto-checkout the
sibling repos by owner.
