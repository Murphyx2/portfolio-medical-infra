# Test Users & Credentials (local dev only)

Credentials for the MedicalConsultations stack running via Docker Compose.
These are local development accounts only — do not use outside the dev environment.

## Users by role

| Username    | Password      | Role            | Can do (summary) |
|-------------|---------------|-----------------|------------------|
| `admin`     | `AdminPass123!` | ADMIN           | Everything: users, centers, medicines, patients, records, appointments |
| `doctor`    | `Pass123!x`   | DOCTOR          | Manage medical records, consultation logs, patients; complete appointments |
| `receptionist` | `Pass123!x`  | RECEPTIONIST    | Manage patients and appointments; cannot touch records/users |
| `nurse`     | `Pass123!x`   | NURSE           | Manage medical records (read/write); cannot manage patients |
| `it`        | `Pass123!x`   | IT              | Manage users, centers, medicines; patient PII is masked/redacted |
| `cm`        | `Pass123!x`   | CENTER_MANAGER  | Read-only overview of centers and patients |

## Access

- Web app: http://localhost:5173  (login page)
- Swagger / API docs: http://localhost:8000/api/docs/
- API root: http://localhost:8000/api

## Notes

- Extra ad-hoc users may exist in the DB from testing (`drdiaz`, `center`, etc.) — ignore them.
- Patient PII is encrypted at rest; `it` and `receptionist` receive redacted data in API responses.
- If a user cannot log in, recreate the stack's data or ask to have the password reset.
