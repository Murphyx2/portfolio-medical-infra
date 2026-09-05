# Backup & Restore

All PHI in this system — patient rows, consultation logs, audit entries, and clinical
images — lives in exactly two Docker named volumes on a single laptop-class host:

- `medicalconsultations_pgdata` — the Postgres data directory (everything in the
  database: patients, encounters, records, appointments, audit log, users, etc.)
- `medicalconsultations_media_volume` — uploaded clinical images

Neither volume has any built-in redundancy. Volume corruption, `docker compose down -v`,
host loss, or a bad boot-time migration destroys all data permanently unless a backup
exists. Since soft-delete means the database only ever grows, there is no "undo" inside
the running system either — a backup is the only recovery path.

The tooling is three PowerShell scripts in `infra/scripts/`. There's no scheduler wired up
by default — run `backup_db.ps1` manually, or register it with Windows Task Scheduler (or
cron, if this ever moves to a Linux host) if this stack starts holding real data.
`schedule_backup_task.ps1` (run as Administrator) automates the Task Scheduler registration
in one command instead of the multi-step GUI walkthrough.

## Creating a backup

```powershell
cd infra
.\scripts\backup_db.ps1
```

This does three things:

1. Runs `pg_dump -Fc` (Postgres's custom binary format) inside the running `db`
   container, writing to a file inside the container first, then pulling it out via
   `docker compose cp` — this avoids piping binary dump output through PowerShell's text
   pipeline, which can silently corrupt binary data on Windows.
2. Tars the `medicalconsultations_media_volume` contents via a disposable `alpine`
   container.
3. Writes both files, timestamped, into `infra/backups/` (created automatically) —
   `pgdata_<timestamp>.dump` and `media_<timestamp>.tar.gz` — then deletes anything in
   that folder older than the retention window.

**Options:**

| Flag | Default | Purpose |
|---|---|---|
| `-RetentionDays` | `14` | Delete backup files older than this many days, so the folder doesn't grow forever. |
| `-BackupDir` | `infra/backups` | Where to write backups. Point this at a different drive/share for off-host storage — see "Off-host copies" below. |

The `db` service must already be running (`docker compose up -d db` at minimum).

## Restoring a backup

```powershell
cd infra
.\scripts\restore_db.ps1 -DumpFile ".\backups\pgdata_2026-08-21T140005.dump" `
                         -MediaArchive ".\backups\media_2026-08-21T140005.tar.gz" `
                         -Confirm
```

This is **destructive** — it overwrites the current database (`pg_restore --clean
--if-exists`) and replaces everything in the media volume. The script refuses to run
without `-Confirm`. `-MediaArchive` is optional; omit it to restore the database only.

### Two things to do after every restore

1. **Re-run migrations.** A `pg_dump` is self-contained — it captures the full schema as
   it stood at backup time, so a backup is never "invalidated" by migrations that ran
   afterward. But *restoring* an old dump rolls the schema back to that point. Any
   migrations that ran after the backup — including data-backfill migrations like the
   `patients` app's helper-column backfills — need to be re-applied:

   ```bash
   cd backend
   python manage.py migrate
   ```

2. **Check the PII encryption key.** If `PII_FIELD_KEY` was rotated (via `manage.py
   reencrypt_pii`) between the backup and the restore, the restored encrypted PII
   columns (patient names, cedula, NSS, etc.) are undecryptable under the *current* key
   — `decrypt_token` fails closed rather than returning garbage. Either restore using the
   key that was active when the backup was taken, or immediately re-run:

   ```bash
   python manage.py reencrypt_pii --old-key <THE_KEY_ACTIVE_AT_BACKUP_TIME>
   ```

## Handling the backup files themselves

`infra/backups/` is gitignored — **never commit a `.dump` or `.tar.gz` file from this
folder.** A `pgdata_*.dump` file contains the same PHI as the live database (Postgres
data isn't Fernet-encrypted the way individual patient fields are inside the app, and the
media tar contains raw clinical images) — it needs the same access control as the
production database itself: restrict who can read the backup folder/drive, and encrypt or
access-control any off-host copy.

## Off-host copies

The scripts today only write to a local directory (`-BackupDir`). For real deployments,
copy the contents of that directory somewhere off the host after each backup run — a
second drive, network share, or cloud storage bucket, with encryption and access control
matching the sensitivity of the data. This wasn't built as a second automated "adapter"
in the scripts themselves (there's no off-host target configured anywhere in this repo
yet, and picking one speculatively wasn't worth doing) — treat it as a small follow-up:
point `-BackupDir` at the off-host location directly, or add a copy step after
`backup_db.ps1` runs.

## Rehearsing the drill

Don't wait for a real incident to find out the restore doesn't work. Periodically:

1. `.\scripts\backup_db.ps1`
2. `.\scripts\restore_db.ps1 -DumpFile <the file just created> -MediaArchive <...> -Confirm`
3. `python manage.py check` and `python manage.py showmigrations` from `backend/` to
   confirm the restored stack is healthy and current.
4. Hit `/api/health/` to confirm the app is actually serving.

This was done once end-to-end when the scripts were built (2026-08-21): backup → restore
→ `manage.py check` clean → all migrations still applied → `/api/health/` returned 200.
