# Deploying MedicalConsultations on a Private Network

A complete, beginner-friendly walkthrough for putting this application on a
server that lives inside a private network (a clinic's LAN, an office network,
a home network) — reachable by the computers and phones on that network, but
**never** exposed to the public internet.

This guide assumes you have never used Docker, Git, or a terminal before. Every
step spells out exactly what to type. Windows is the primary path; wherever a
step differs on Linux, a **Linux** box immediately follows the Windows steps.

> **What "private network" means here:** all machines involved — the server and
> everyone who uses the app — are on the same local network (same office Wi-Fi,
> same building switch, or a VPN that behaves like one). Nothing in this guide
> opens the app to the wider internet, and none of the steps involve
> port-forwarding on your router. If you ever *do* want internet-facing access,
> that needs additional work (a real domain name, a real TLS certificate, a
> reviewed firewall/reverse-proxy setup) that is out of scope for this guide —
> don't improvise it from these steps.

---

## Table of contents

1. [What you're deploying](#1-what-youre-deploying)
2. [Before you start](#2-before-you-start)
3. [Step 1 — Install Docker](#3-step-1--install-docker)
4. [Step 2 — Get the code onto the server](#4-step-2--get-the-code-onto-the-server)
5. [Step 3 — Configure the environment file](#5-step-3--configure-the-environment-file)
6. [Step 4 — Find the server's network address](#6-step-4--find-the-servers-network-address)
7. [Step 5 — Start the application](#7-step-5--start-the-application)
8. [Step 6 — Create the admin account](#8-step-6--create-the-admin-account)
9. [Step 7 — Open it from other computers on the network](#9-step-7--open-it-from-other-computers-on-the-network)
10. [Step 8 — Verify everything works](#10-step-8--verify-everything-works)
11. [Day-to-day operation](#11-day-to-day-operation)
12. [Backups](#12-backups)
13. [Troubleshooting](#13-troubleshooting)
14. [Security notes](#14-security-notes)
15. [Appendix — full reference](#15-appendix--full-reference)
16. [Configuring Comunicaciones for production (staff email & patient WhatsApp)](#16-configuring-comunicaciones-for-production-staff-email--patient-whatsapp)

---

## 1. What you're deploying

The application is three things working together, run by a tool called
**Docker** so you don't have to install Python, Node.js, or a database by hand:

| Piece | What it is |
|---|---|
| **Database** (`db`) | Stores all data (patients, records, appointments). |
| **Cache** (`cache`) | Speeds things up internally. |
| **Backend** (`backend`) | The API — the "brain" of the app. |
| **Frontend** (`frontend`) | The website you and your staff actually see and click on, served over **HTTPS** (encrypted) with a lock icon in the browser (using a self-signed certificate — see [Step 7](#9-step-7--open-it-from-other-computers-on-the-network)). |
| **Communications worker** (`communications_worker`) | Sends staff email notices and patient WhatsApp appointment reminders in the background (the "Comunicaciones" module — see [section 16](#16-configuring-comunicaciones-for-production-staff-email--patient-whatsapp) for production setup). |

All five run inside **containers** — small, self-contained boxes that each hold
one piece of the app. You start, stop, and update them together with a tool
called **Docker Compose**, using one command from a folder called `infra/`.

Once running, anyone on the same private network can open a web browser and go
to `https://<server's-address>` to use the app. The database and cache are
never reachable from outside the containers themselves — only the website
(frontend) is exposed, and only on the local network.

---

## 2. Before you start

You will need:

- **A server machine** that stays powered on — a desktop, an old PC repurposed
  as a server, or a dedicated server box. Windows 10/11 or Windows Server, or a
  Linux distribution (this guide uses Ubuntu/Debian commands for Linux;
  other distributions are similar but package manager commands differ).
- **Administrator access** on that machine (Windows: an admin account; Linux: a
  user who can run `sudo`).
- The three project folders — `backend`, `frontend`, `infra` — available to
  copy onto the server (from Git, a USB drive, or a network share).
- About 30–60 minutes, and roughly 4 GB of free disk space for Docker plus the
  application's data.

**A few words you'll see repeatedly:**

- **Terminal / Command line**: a text window where you type commands instead of
  clicking. On Windows, use **PowerShell** (search "PowerShell" in the Start
  menu, right-click, "Run as Administrator" when a step needs it). On Linux,
  use your distribution's **Terminal** app.
- **IP address**: the "phone number" of a computer on the network, e.g.
  `192.168.1.42`. You'll look yours up in [Step 4](#6-step-4--find-the-servers-network-address).
- **Container**: a lightweight, isolated box that runs one piece of the app.
  Docker starts/stops/rebuilds these for you.

Every command below is meant to be **copied and pasted** exactly as written,
except where a command shows a placeholder in `<angle brackets>` — replace the
whole placeholder, brackets included, with your own value.

---

## 3. Step 1 — Install Docker

### Windows

1. Go to **docker.com** and download **Docker Desktop for Windows**, or ask
   whoever manages your organization's software to install it for you.
2. Run the installer. When it asks about the backend, keep the default
   **WSL 2** option checked.
3. Restart the computer if the installer asks you to.
4. Open Docker Desktop once — it needs to be running in the background for any
   of the later steps to work (look for the whale icon in the system tray).
5. Open PowerShell and confirm it installed correctly:
   ```powershell
   docker --version
   docker compose version
   ```
   Both should print a version number, not an error.

### Linux

1. Open a terminal and run the official install script:
   ```bash
   curl -fsSL https://get.docker.com | sh
   ```
2. Add your user to the `docker` group so you don't need `sudo` for every
   command (log out and back in afterward for this to take effect):
   ```bash
   sudo usermod -aG docker $USER
   ```
3. Make sure the Compose plugin is present (recent Docker installs include it;
   if `docker compose version` below fails, install it explicitly):
   ```bash
   sudo apt-get update && sudo apt-get install -y docker-compose-plugin
   ```
4. Confirm:
   ```bash
   docker --version
   docker compose version
   ```

> This app's commands always use **`docker compose`** (two words, a space) —
> the modern built-in plugin — never the older standalone `docker-compose`
> (one word, a hyphen). If you only have the old tool, install the plugin
> above instead of relying on it.

---

## 4. Step 2 — Get the code onto the server

The three folders (`backend`, `frontend`, `infra`) must end up **next to each
other in the same parent folder** — the setup expects `infra/../backend` and
`infra/../frontend` to exist, because that's literally how the config finds
the other two folders to build them.

```
MedicalConsultations/
├── backend/
├── frontend/
└── infra/        <- you will run all commands from inside here
```

**If you have Git set up** (ask your developer if you're not sure), clone all
three repositories side by side:

```bash
git clone <backend-repo-url> backend
git clone <frontend-repo-url> frontend
git clone <infra-repo-url> infra
```

**If you don't use Git**, simply copy the three folders (via USB drive, network
share, or however you received them) into one parent folder, keeping the exact
names `backend`, `frontend`, `infra` and the sibling layout shown above.

Once copied, open a terminal and move into the `infra` folder — every command
for the rest of this guide is run from there:

```bash
cd path/to/MedicalConsultations/infra
```

---

## 5. Step 3 — Configure the environment file

The app reads its passwords and settings from a file named `.env` inside
`infra/`. This file is never shared or checked into Git — you create your own
copy on each server, with your own values.

1. Copy the template:
   - **Windows (PowerShell):** `copy .env.example .env`
   - **Linux:** `cp .env.example .env`

2. Open `.env` in a text editor (Notepad, Notepad++, `nano`, whatever's
   available) and fill in the values below. Everything else in the file can be
   left at its default.

| Variable | What it's for | How to set it |
|---|---|---|
| `DJANGO_SECRET_KEY` | Cryptographic key the backend uses internally. **Secret — never share.** | See command below. |
| `POSTGRES_PASSWORD` | Database password. **Secret.** | See command below. |
| `REDIS_PASSWORD` | Cache password (required for the production setup this guide uses). **Secret.** | See command below. |
| `PII_FIELD_KEY` | Encryption key protecting patient data (names, birth dates, phone numbers, etc.) in the database. **Secret — and see the warning below.** | See command below. |
| `DJANGO_ALLOWED_HOSTS` | Which addresses the backend will accept requests for. | Add the server's IP address — see [Step 4](#6-step-4--find-the-servers-network-address). |
| `DJANGO_CORS_ALLOWED_ORIGINS` | Which web origins may call the API. | Add `https://<server's-address>` — see [Step 4](#6-step-4--find-the-servers-network-address). |
| `TZ` | Timezone used for dates/timestamps in the app. | Set to your local timezone, e.g. `America/Santo_Domingo`. |

**Generating the three secret values.** Each is a long random string — don't
type your own; generate them with these one-liners. If Python is installed on
the server, run them directly:

```bash
# DJANGO_SECRET_KEY
python -c "import secrets; print(secrets.token_urlsafe(64))"

# PII_FIELD_KEY
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

If Python isn't installed on the server itself (common — the app only needs it
*inside* its containers), generate them using a temporary throwaway container
instead, which works identically on Windows and Linux:

```bash
docker run --rm python:3.13-alpine python -c "import secrets; print(secrets.token_urlsafe(64))"
docker run --rm python:3.13-alpine sh -c "pip install -q cryptography && python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
```

For `POSTGRES_PASSWORD` and `REDIS_PASSWORD`, any long random password works —
reuse one of the `secrets.token_urlsafe(64)` outputs above, or use a password
manager's generator.

Paste each generated value into the matching line in `.env`, e.g.:

```
DJANGO_SECRET_KEY=the-long-random-string-you-generated
POSTGRES_PASSWORD=another-long-random-string
REDIS_PASSWORD=yet-another-long-random-string
PII_FIELD_KEY=the-fernet-key-you-generated
```

> ⚠️ **Critical — read before continuing.** Once the app has real patient data
> in it, **`PII_FIELD_KEY` must never be changed.** Changing it makes every
> existing patient record permanently unreadable — there is no way to recover
> the data afterward without the original key. Set it once, correctly, before
> going live, and keep a secure backup copy of the `.env` file itself (see
> [Backups](#12-backups)). If a key ever genuinely must be rotated, that
> requires a dedicated migration command (`reencrypt_pii`), not just editing
> the file — see [Troubleshooting](#13-troubleshooting).
>
> ⚠️ Never commit `.env` to Git, email it, or store it anywhere outside the
> server and a secure backup. It contains every password and encryption key
> the app relies on.

---

## 6. Step 4 — Find the server's network address

You need the server's private IP address so other computers on the network can
reach it, and so you can put it into `.env` above.

**Windows:**
```powershell
ipconfig
```
Look for `IPv4 Address` under your active network adapter (Wi-Fi or Ethernet),
e.g. `192.168.1.42`.

**Linux:**
```bash
hostname -I
# or
ip addr
```
Look for an address starting with `192.168.`, `10.`, or `172.16.`–`172.31.` —
these ranges are reserved for private networks.

Now go back to `.env` and fill in the two host/origin lines using that address:

```
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,backend,192.168.1.42
DJANGO_CORS_ALLOWED_ORIGINS=https://192.168.1.42
```

(Replace `192.168.1.42` with your server's actual address in both lines.)

> A server's IP address can change after a reboot or router restart, depending
> on your network setup. If that happens, the app will stop accepting requests
> for the new address until you update `.env` to match and restart the
> `backend` container (see [Day-to-day operation](#11-day-to-day-operation)).
> Ask whoever manages your network about reserving (a "DHCP static lease" or
> "static IP") this address for the server so it doesn't change.

---

## 7. Step 5 — Start the application

From inside the `infra` folder, run:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

This one command:

1. Downloads and builds everything the app needs (first run takes several
   minutes; later runs are much faster).
2. Generates a self-signed HTTPS certificate automatically (more on this in
   [Step 7](#9-step-7--open-it-from-other-computers-on-the-network)).
3. Sets up the database.
4. Starts all five pieces of the app in the background (`-d` = "detached",
   i.e. it doesn't tie up your terminal).

Watch it come up:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

You should see five containers (`mc_prod_db`, `mc_prod_cache`,
`mc_prod_backend`, `mc_prod_frontend`, `mc_prod_communications_worker`) listed
as `running` or `healthy`. If one isn't, check its logs:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f
# or just one service, e.g.:
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f backend
```
Press `Ctrl+C` to stop watching logs (this does not stop the app).

> If `mc_prod_frontend` fails to start the very first time and the logs
> mention a missing certificate, that's a brief startup race — the certificate
> generator (`cert-init`) sometimes finishes a second or two after nginx tries
> to read it. Just re-run the `up -d` command above once; it's safe to run
> repeatedly.

---

## 8. Step 6 — Create the admin account

You need one administrator login to actually use the app. Create it with:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py create_admin --username admin --email admin@example.com --password "ChangeMe123!"
```

Replace `admin`, `admin@example.com`, and especially the password with your
own values — **do not leave the example password in place.** You'll use these
credentials to log into the website in the next step.

---

## 9. Step 7 — Open it from other computers on the network

### Allow the connection through the firewall

By default, the server's own firewall blocks incoming connections on most
ports. You need to allow ports **443** (HTTPS, the website) and, if you want
it, **80** (which only redirects to 443).

**Windows** — open PowerShell **as Administrator**:
```powershell
New-NetFirewallRule -DisplayName "MedicalConsultations HTTPS" `
  -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow -Profile Private
New-NetFirewallRule -DisplayName "MedicalConsultations HTTP Redirect" `
  -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow -Profile Private
```

**Linux** (using `ufw`, common on Ubuntu/Debian):
```bash
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
```
(If your Linux server uses `firewalld` instead: `sudo firewall-cmd
--permanent --add-port=443/tcp --add-port=80/tcp && sudo firewall-cmd
--reload`.)

> ⚠️ **Never forward these ports on your router.** The firewall rules above
> only open the ports on your local network (`-Profile Private` on Windows
> keeps it off Public/Domain networks too). Port-forwarding on the router
> would expose the app to the entire internet — do not do this. This
> deployment is designed and reviewed for private-network use only.

### Browse to the app

From any other computer or phone **on the same network**, open a browser and
go to:

```
https://192.168.1.42
```

(Replace with your server's actual IP address from [Step 4](#6-step-4--find-the-servers-network-address).)

### About the "not secure" / certificate warning

The browser will show a warning like "Your connection is not private" or "not
secure." This is **expected** — the app generated its own self-signed HTTPS
certificate rather than buying one from a public certificate authority (which
requires a public domain name, something a private-network deployment doesn't
have). The connection is still encrypted; the warning only means the browser
doesn't recognize who *issued* the certificate.

Because this is a trusted private network you control, it's safe to proceed:

- **Chrome/Edge:** click "Advanced," then "Proceed to `<address>` (unsafe)."
- **Firefox:** click "Advanced," then "Accept the Risk and Continue."

Each device will show this warning once (or after the certificate is
regenerated). If you later obtain a real certificate for an internal domain
name, it can be mounted in place of the self-signed one — that's beyond this
guide's scope; ask your developer.

---

## 10. Step 8 — Verify everything works

1. Log in at `https://<server-address>` with the admin credentials from
   [Step 6](#8-step-6--create-the-admin-account).
2. Confirm the health check responds (from the server itself, or any machine
   on the network):
   ```bash
   curl -k https://192.168.1.42/api/health/
   ```
   (`-k` tells `curl` to ignore the self-signed certificate warning, same idea
   as clicking through it in a browser.) A healthy response returns without an
   error.
3. Have another device on the network open the same address and confirm it
   also loads and logs in.

If all of that works, the deployment is complete and ready for regular use.

---

## 11. Day-to-day operation

All commands below run from the `infra/` folder. To keep things shorter, note
that every command in this section targets the **production** stack, so it
needs both `-f` flags — consider setting a shell alias/shortcut if you'll be
typing these often.

```bash
# Stop the app (data is preserved)
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# Start it again
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Check status
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps

# View logs
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f [service-name]
```

**After receiving updated code** (a new version of `backend` or `frontend`
from your developer), rebuild and restart:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

> If the update included new database changes ("migrations"), they run
> automatically every time the `backend` container starts — but only if it
> actually restarts. A container that's just quietly running with old code
> won't pick up new migrations on its own; the `--build` + `up -d` command
> above always restarts it, so prefer that over trying to skip steps.

**Changing day-to-day settings** (login lockout rules, session lifetimes, rate
limits, maximum upload size, page size, etc.) usually does **not** require
touching Docker or redeploying at all — an administrator can change these
live from inside the app itself, under its Settings page. Reserve the
redeploy steps above for actual code updates.

> ⚠️ **Destructive, avoid unless you mean it:** adding `-v` to `down` (i.e.
> `down -v`) permanently deletes the database and all uploaded files. Never
> run this on a server with real data unless you have a current backup and
> intend to wipe everything.

---

## 12. Backups

The app's data lives in two places that must both be backed up together: the
database and the folder of uploaded media (record images).

### Running a backup

From `infra/`, using **PowerShell** (see the note below for Linux):

```powershell
./scripts/backup_db.ps1
```

This creates two timestamped files in `infra/backups/`:
- `pgdata_<timestamp>.dump` — the full database.
- `media_<timestamp>.tar.gz` — all uploaded images/files.

By default it keeps 14 days of backups and deletes older ones automatically.
To change that: `./scripts/backup_db.ps1 -RetentionDays 30`. To change where
backups are written: `./scripts/backup_db.ps1 -BackupDir "D:\Backups"`.

### Restoring a backup

```powershell
./scripts/restore_db.ps1 -DumpFile "infra/backups/pgdata_2026-08-21T140005.dump" `
  -MediaArchive "infra/backups/media_2026-08-21T140005.tar.gz" -Confirm
```

The `-Confirm` flag is required on purpose — the script refuses to run without
it, since restoring **replaces all current data** with the backup's data.

After restoring, run the two follow-up steps the script itself will remind you
about:
1. Apply any pending database migrations:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py migrate
   ```
2. If `PII_FIELD_KEY` in `.env` has changed since that backup was taken, run
   the re-encryption command with the *old* key before anything else — see
   [Troubleshooting](#13-troubleshooting).

### Running backups on Linux

The backup/restore scripts are written in **PowerShell**, which also runs on
Linux via **PowerShell Core** (`pwsh`) — there is currently no separate Bash
version of these scripts.

1. Install PowerShell Core on the Linux server (Ubuntu example):
   ```bash
   sudo apt-get update && sudo apt-get install -y wget apt-transport-https software-properties-common
   wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
   sudo dpkg -i packages-microsoft-prod.deb
   sudo apt-get update && sudo apt-get install -y powershell
   ```
2. Run the same scripts with `pwsh` instead of relying on the `.ps1`
   double-click behavior Windows has:
   ```bash
   pwsh ./scripts/backup_db.ps1
   pwsh ./scripts/restore_db.ps1 -DumpFile "infra/backups/pgdata_....dump" -Confirm
   ```

### Scheduling backups automatically

Nothing in the repo schedules backups for you — set up a recurring job
yourself:

**Windows — Task Scheduler:**
1. Open **Task Scheduler** → **Create Basic Task**.
2. Name it, choose a daily (or preferred) trigger.
3. Action: **Start a program** → Program: `pwsh.exe` (or `powershell.exe`) →
   Arguments: `-File "C:\path\to\infra\scripts\backup_db.ps1"`.
4. Finish, then right-click the task → **Run** once to confirm it works.

**Linux — cron**, running the script via PowerShell Core:
```bash
crontab -e
```
Add a line to run it every night at 2 AM:
```
0 2 * * * pwsh /path/to/infra/scripts/backup_db.ps1 >> /var/log/mc-backup.log 2>&1
```

### Copying backups off the server

The scripts only write to a local folder on the server itself — if that
machine's disk fails, the backups fail with it. Periodically copy the contents
of `infra/backups/` to a second drive, a network share, or off-site/cloud
storage; there is no built-in automation for this step, so it has to be a
manual or separately-scheduled habit. Treat backup files with the same care as
the live database — they contain the same patient data.

---

## 13. Troubleshooting

**A port is already in use / the app won't start.**
Check what's already listening:
- Windows: `Get-NetTCPConnection -LocalPort 443`
- Linux: `sudo ss -tulpn | grep :443`

Something else on the machine (another web server, a previous instance of this
app) is likely using that port. Stop it, or see `docker-management.md` for how
to change which port a service binds to.

**A container keeps restarting or shows "unhealthy."**
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f <service-name>
```
Read the last lines of the log for the actual error. Common first-boot cause:
the `frontend` container starting a moment before its certificate is ready —
see the note at the end of [Step 5](#7-step-5--start-the-application).

**Browser shows a certificate warning.**
Expected — see [Step 7](#9-step-7--open-it-from-other-computers-on-the-network). Not
a sign of a problem.

**Forgot the admin password.**
Create a new admin account with the same command from
[Step 6](#8-step-6--create-the-admin-account) using a different username, or
ask your developer about resetting an existing account's password through
Django's admin tools.

**Accidentally changed `PII_FIELD_KEY` and now can't read patient data.**
Don't panic, don't restart repeatedly — put the **old** key back in `.env`
immediately so the app can read existing data again, then have your developer
run the key-rotation command properly if a change is genuinely needed:
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py reencrypt_pii --old-key <OLD_KEY>
```
This safely re-encrypts every record with the new key instead of just leaving
old data unreadable. Do this only with guidance if you're unsure — it touches
every patient record in the database.

**The server's IP address changed and nothing loads anymore.**
Update `DJANGO_ALLOWED_HOSTS` and `DJANGO_CORS_ALLOWED_ORIGINS` in `.env` to
the new address (see [Step 4](#6-step-4--find-the-servers-network-address)),
then:
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate backend frontend
```

---

## 14. Security notes

- The database and cache containers publish **no ports at all** in this setup
  — they can only be reached by the other containers, never directly from the
  network. This is intentional and already configured correctly; don't add
  port mappings for them.
- The self-signed certificate is appropriate **only** because this deployment
  is private-network-only. Don't reuse the same setup for anything reachable
  from the public internet.
- Keep `.env` readable only by administrators. It holds every password and
  encryption key the app depends on.
- Never set `DJANGO_DEBUG=true` on a real deployment — the production compose
  file already forces it to `false`, and the app itself refuses to start in
  production mode with a missing or default-looking secret key, database
  password, or `PII_FIELD_KEY`. Don't try to work around that failure by
  weakening these values; fix the actual `.env` value instead.
- Every meaningful action in the app (creating, editing, viewing sensitive
  records) is written to an audit log automatically — you don't need to
  configure anything extra for this.

---

## 15. Appendix — full reference

### Full `.env` variable list

| Variable | Sensitive? | Purpose |
|---|---|---|
| `DJANGO_SECRET_KEY` | Yes | Backend cryptographic key. |
| `DJANGO_DEBUG` | — | Must stay `false` in this deployment; prod overlay enforces this. |
| `DJANGO_ALLOWED_HOSTS` | — | Hostnames/IPs the backend accepts requests for. |
| `DJANGO_CORS_ALLOWED_ORIGINS` | — | Origins allowed to call the API cross-origin. |
| `TZ` | — | Server timezone for dates/timestamps. |
| `POSTGRES_DB` | — | Database name. |
| `POSTGRES_USER` | — | Database username. |
| `POSTGRES_PASSWORD` | Yes | Database password. |
| `POSTGRES_HOST` | — | Always `db` inside Docker — leave as-is. |
| `POSTGRES_PORT` | — | Port Postgres listens on inside its own container. |
| `REDIS_PASSWORD` | Yes | Cache password, required by the production overlay. |
| `REDIS_URL` | — | Built from `REDIS_PASSWORD` automatically — leave as-is. |
| `JWT_ACCESS_LIFETIME_MINUTES` | — | How long a login session's access token lasts. |
| `JWT_REFRESH_LIFETIME_DAYS` | — | How long a user can stay logged in before re-authenticating. |
| `PII_FIELD_KEY` | Yes | Encrypts patient personal data at rest. **Never change once real data exists** — see [Step 3](#5-step-3--configure-the-environment-file). |
| `PROXY_TARGET` | — | Only relevant if running the frontend outside Docker; irrelevant to this deployment. |
| `EMAIL_HOST` / `EMAIL_PORT` / `EMAIL_HOST_USER` / `EMAIL_USE_TLS` / `DEFAULT_FROM_EMAIL` | — | Comunicaciones staff email (SMTP). Optional — see [section 16](#16-configuring-comunicaciones-for-production-staff-email--patient-whatsapp). |
| `EMAIL_HOST_PASSWORD` | Yes | Mailbox password / app password for the above. |

### Command cheat-sheet (production stack, run from `infra/`)

```bash
# Start / rebuild
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# Stop (keeps data)
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# Status
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps

# Logs
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f [service]

# Shell into backend
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend sh

# Database shell
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec db psql -U <POSTGRES_USER> -d <POSTGRES_DB>

# Run a database migration manually
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py migrate

# Create an admin user
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py create_admin --username <name> --email <email> --password "<password>"

# Backup / restore (PowerShell / PowerShell Core)
./scripts/backup_db.ps1
./scripts/restore_db.ps1 -DumpFile "<path>" -MediaArchive "<path>" -Confirm
```

### Where things live once deployed

| What | Address |
|---|---|
| The app (website) | `https://<server-IP>` |
| API health check | `https://<server-IP>/api/health/` |

Django admin (`/admin/`) and API docs (`/api/docs/`) exist but are restricted
to Admin/IT accounts — day-to-day use only needs the main website address
above.

---

## 16. Configuring Comunicaciones for production (staff email & patient WhatsApp)

**Comunicaciones** is the module that sends staff notices by email and
appointment reminders to patients over WhatsApp. It runs on a fifth
background container, **`communications_worker`**
(`mc_prod_communications_worker` in this stack) — already started
automatically by the same `up -d --build` command from
[Step 5](#7-step-5--start-the-application); there is no separate service to
install. It polls every 60 seconds and has nothing to configure on its own —
the two channels below are configured separately.

### Staff email

Comunicaciones reuses the clinic's own mailbox — it never sets up a second
email service. Add these to `.env` (they're optional; leave `EMAIL_HOST`
blank and staff-email sending simply stays off until it's filled in):

| Variable | What it's for |
|---|---|
| `EMAIL_HOST` | Your mail provider's SMTP server, e.g. `smtp.gmail.com` or `smtp.office365.com`. |
| `EMAIL_PORT` | Usually `587` (STARTTLS). |
| `EMAIL_HOST_USER` | The mailbox's login/address. |
| `EMAIL_HOST_PASSWORD` | Its password — for Gmail/Google Workspace this must be an **App Password**, not the regular account password. **Secret.** |
| `EMAIL_USE_TLS` | Leave `true`. |
| `DEFAULT_FROM_EMAIL` | The "From" address staff see, e.g. `no-reply@yourclinic.com`. |

After editing `.env`, restart the backend and worker so they pick up the new
values:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate backend communications_worker
```

Test it once logged in as an Admin: **Comunicaciones → Ajustes → Correo →
"Enviar correo de prueba."**

### Patient WhatsApp

Unlike email, WhatsApp is **not** configured through `.env` at all — an Admin
enters it directly in the app, under **Comunicaciones → Ajustes → WhatsApp**,
after logging in. Nothing sends until this is done; the master switch stays
off by default.

1. **Provision WhatsApp Business Cloud API access with Meta first** — that
   process (business verification, app creation) is Meta's own and outside
   this guide. You'll come out of it with four things: a **phone number
   ID**, a **business account ID**, a permanent **access token**, and an
   **app secret**.
2. Log in as Admin → **Comunicaciones → Ajustes → WhatsApp** → paste those
   four values, confirm the default country code (prefilled `+1` for the
   Dominican Republic), set the reminder lead time (default 24 hours before
   the appointment), then turn on **"Activar WhatsApp a pacientes."**
3. **Templates.** WhatsApp only ever sends Meta-**pre-approved** template
   messages — never free text. Before any patient WhatsApp will actually go
   out, create/activate one template row per kind under **Comunicaciones →
   Plantillas** (`cita_creada`, `cita_recordatorio`, `cita_reagendada`,
   `cita_cancelada`), matching the exact template name and language Meta
   approved for your account. A missing or inactive template for a kind
   fails just that one send with a clear in-app message ("Falta plantilla de
   WhatsApp para {tipo}") instead of breaking anything else.
4. Test it with **"Enviar WhatsApp de prueba"** on the same Ajustes page
   (stays disabled until the token and phone number ID are both saved).

> ⚠️ **The webhook needs the public internet — this guide's private-network
> setup does not provide that.** Meta's servers deliver delivery-status
> updates (Sent → Delivered → Read) and inbound replies — including a
> patient texting **STOP**/**SALIR**/**NO**/**CANCELAR** to opt out — by
> calling a webhook URL on your server, which means Meta must be able to
> reach your server over the internet. This deployment, as described in this
> guide, is reachable only from your local network (see the note at the top
> of this document), so the webhook cannot be wired up as-is.
>
> **What still works without it:** sending itself only needs *outbound*
> connectivity (your server calling out to `graph.facebook.com`), so
> appointment reminders and notices still send normally.
>
> **What doesn't:** delivery status will sit at "Sent" and never advance to
> "Delivered"/"Read" in the Comunicaciones log, and a patient replying STOP
> will **not** be opted out automatically — a staff member has to turn off
> **"Notificaciones por WhatsApp"** on that patient's record by hand instead
> if the patient asks to stop receiving messages.
>
> If your organization later decides to expose this deployment to the public
> internet (a real domain name, a real TLS certificate, a reviewed
> reverse-proxy/firewall setup — all outside this guide's scope; get a
> developer or ops professional involved for that), only then register the
> webhook: copy the read-only **Webhook URL** shown on the Ajustes →
> WhatsApp page, set a **Verify Token** on that same page, and enter both in
> the Meta App dashboard under WhatsApp → Configuration → Webhook,
> subscribed to the `messages` field.

### If messages seem stuck

Queued email/WhatsApp messages send within about a minute (the worker's poll
interval). If something sits in "Queued" longer than that, check the
worker's own logs:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f communications_worker
```

---

*See also, in this same folder: `docker-management.md` for deeper compose-file
mechanics and `backups.md` for the full backup/restore design notes.*
