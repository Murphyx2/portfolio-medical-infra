# Test Users & Credentials (local dev only)

Credentials for the MedicalConsultations stack running via Docker Compose.
These are local development accounts only — do not use outside the dev environment.

## Users by role

| Username    | Password      | Role            | Can do (summary) |
|-------------|---------------|-----------------|------------------|
| `admin`     | `AdminPass123!` | ADMIN           | Everything: users, centers, medicines, patients, records, appointments |
| `doctor`    | `Pass123!x`   | DOCTOR          | Manage medical records, consultation logs, patients; complete appointments |
| `receptionist` | `Pass123!x`  | RECEPTIONIST    | Manage patients, appointments and ARS insurers; cannot touch records/users |
| `nurse`     | `Pass123!x`   | NURSE           | Manage medical records (read/write); cannot manage patients |
| `it`        | `Pass123!x`   | IT              | Manage users, centers, medicines; patient PII is masked/redacted |
| `cm`        | `Pass123!x`   | CENTER_MANAGER  | Read-only overview of centers and patients |

## Access

- Web app: http://localhost:5173  (login page)
- Swagger / API docs: http://localhost:8000/api/docs/
- API root: http://localhost:8000/api

## Database access (manual inspection)

Read-only PostgreSQL account for inspecting the database directly (psql / pgAdmin / DBeaver).

| Host | Port | Database | User | Password |
|------|------|----------|------|----------|
| `127.0.0.1` | `5432` | `medicalconsultations` | `db_reviewer` | `a5C2ypLfDhsn1FElPuGANczi` |

- **Read-only:** `CONNECT` + `SELECT` on all tables only; writes/deletes are denied.
- PII columns (names, birth date, phone, address, email, cédula, NSS) are **Fernet-encrypted at rest** — manual DB reads show ciphertext, not plaintext. Use the web app to read PII.
- Example: `docker exec -e PGPASSWORD=a5C2ypLfDhsn1FElPuGANczi mc_db psql -U db_reviewer -d medicalconsultations -c "SELECT count(*) FROM patients_patient;"`

## Notes

- Extra ad-hoc users may exist in the DB from testing (`drdiaz`, `center`, etc.) — ignore them.
- Patient PII is encrypted at rest; `it` and `cm` receive redacted data in API responses (receptionists, doctors, nurses and admins see full PII).
- If a user cannot log in, recreate the stack's data or ask to have the password reset.
