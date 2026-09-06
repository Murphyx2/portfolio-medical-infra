# CI/CD Deployment Pipeline

> Status: **reference design, not yet implemented.** CI (test/build/validate) already runs today via GitHub Actions in all three repos. This document designs the missing CD (continuous deployment) half — automatically shipping a merged `main` commit to the clinic server, with no manual SSH/RDP session required — and gives literal, copy-paste-ready workflow/script content for whenever you decide to build it. Nothing described here has been created in the repos yet.

## 1. Where this fits

### What CI already does today

All three repos (`backend`, `frontend`, `infra`) run a GitHub Actions workflow on push/PR to `dev` and `main` (plus manual `workflow_dispatch`):

| Repo | Workflow | Job | What it does |
|---|---|---|---|
| `backend` | `.github/workflows/ci.yml` | `test` | `pip install -r requirements/dev.txt` → `python manage.py check --settings config.settings.test` → `pytest` |
| `frontend` | `.github/workflows/ci.yml` | `build` | `npm ci` → `npm test` → `npm run build` (type-check + Vite build) |
| `infra` | `.github/workflows/ci.yml` | `compose-config` | `docker compose config --quiet` for both the dev and prod compose stacks — validates the YAML/interpolation only, never actually builds or runs a container |

None of the three builds a deployable artifact, pushes an image, or touches the server. `infra/docs/architecture.md` §6 has carried a placeholder for this since the project's early planning: *"(later) push to registry / deploy to laptop."* This document replaces that placeholder.

### What "deploying an update" means today (manual process)

Per `infra/docs/deployment-guide.md` and `infra/docs/manuales/manual-despliegue.md`, today a human:

1. Gets the latest code onto the server as three **sibling** folders (`backend/`, `frontend/`, `infra/` under one parent) — the compose files' `build: ../backend` / `build: ../frontend` contexts depend on this exact layout.
2. From `infra/`, runs:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
   ```
   This rebuilds the `backend`/`frontend` images from source, and the `backend` container's startup command runs `migrate` + `collectstatic` before `gunicorn` starts — so restarting `backend` is *how* migrations get applied. There's no separate migrate step to forget.
3. Verifies with `docker compose ... ps` (all containers `running`/`healthy`) and a browser/`curl` check against `https://<server-ip>`.

**The pipeline below is a straight automation of these three steps** — not a new process, not a different deployment model (e.g. it does not introduce a container registry; images are still built on the server itself, exactly as today).

## 2. Why a self-hosted runner

GitHub's own (cloud-hosted) runners can only reach your server by an *inbound* connection — typically SSH. The existing deployment docs establish, deliberately, that this server has **no inbound ports**: it sits on a private LAN behind a residential Claro/Altice modem, UPnP and DMZ are off, and nothing is port-forwarded (see `manual-despliegue.md` Chapter 8 / `deployment-guide.md`'s network chapter). Opening SSH to the internet to let a cloud runner in would directly violate that rule, and residential DR connections are also commonly behind CGNAT, so a stable inbound path may not even be reachable.

A **self-hosted GitHub Actions runner** flips the direction: it's a small agent installed *on* the server that polls GitHub over an ordinary outbound HTTPS connection, same as a browser tab. GitHub queues a job for it; the runner picks it up and executes it locally. No inbound port, no SSH key on the internet, no VPN required just for this — it's the standard pattern for "deploy to a machine that isn't reachable from the internet," which describes this server exactly.

## 3. Recommended trigger design

A self-hosted runner on a personal (non-organization) GitHub account registers to **one specific repository** — there's no shared/org-level runner pool available on individual repos. Since only `infra` owns the Docker Compose files that actually perform the deploy, the design is:

- **One runner, registered to `infra`.** It is the only repo that needs one.
- **`infra`'s own push to `main`** triggers a deploy directly (an `infra`-only change, e.g. a compose or `.env.example` edit, should redeploy).
- **`backend` and `frontend` CI**, on a successful `main` build, fire a `repository_dispatch` event *at* `infra`, which the runner picks up and treats identically to its own push trigger.

This means any of the three repos landing a change on `main` results in exactly one redeploy, and all the deploy logic (secrets, scripts, the runner itself) lives in one place instead of being duplicated three times. The alternative — a separate self-hosted runner per repo — was considered and rejected: it triples the number of long-running agents on a resource-constrained box for no functional benefit, since `backend`/`frontend` have nothing to deploy without `infra`'s compose files anyway.

## 4. Setting up the runner

1. In the `infra` repo on GitHub: **Settings → Actions → Runners → New self-hosted runner**. Pick the target OS (Windows x64 for Windows 10/11/Server, Linux x64 for a Linux server) — GitHub generates a one-time registration token and the exact download/config commands for that OS.
2. Run the generated `config.cmd` (Windows) or `config.sh` (Linux) on the server, giving it a label, e.g. `clinic-server`, so the deploy workflow can target it explicitly (`runs-on: [self-hosted, clinic-server]`) rather than any self-hosted runner that might exist later.
3. **Install it as a service**, not an interactive session — this is what lets it survive reboots and keep working with nobody logged in:
   - **Windows:** `.\svc.cmd install` then `.\svc.cmd start` (run as Administrator once, in the runner's install folder).
   - **Linux:** `sudo ./svc.sh install` then `sudo ./svc.sh start`.
4. Use a **dedicated, low-privilege OS account** to run the service rather than a personal admin account — it only needs permission to run `docker`/`docker compose` and read/write inside the `MedicalConsultations` folder tree. On Windows, add that account to the `docker-users` group; on Linux, add it to the `docker` group.
5. Verify: the new runner shows as **Idle** under Settings → Actions → Runners in GitHub within a minute of the service starting.

## 5. The deploy workflow

Create `infra/.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [main]
  repository_dispatch:
    types: [deploy]

concurrency:
  group: production-deploy
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: [self-hosted, clinic-server]
    steps:
      - name: Checkout infra
        uses: actions/checkout@v4

      - name: Pull latest backend and frontend
        shell: pwsh
        run: |
          git -C ../backend fetch origin main
          git -C ../backend reset --hard origin/main
          git -C ../frontend fetch origin main
          git -C ../frontend reset --hard origin/main

      - name: Backup before deploying
        shell: pwsh
        run: ./scripts/backup_db.ps1

      - name: Build and restart the stack
        run: docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

      - name: Verify containers are healthy
        shell: pwsh
        run: |
          Start-Sleep -Seconds 15
          $bad = docker compose -f docker-compose.yml -f docker-compose.prod.yml ps --format json |
            ConvertFrom-Json | Where-Object { $_.State -ne 'running' -and $_.Health -notin @('healthy', '') }
          if ($bad) { throw "Unhealthy container(s) after deploy: $($bad.Name -join ', ')" }

      - name: Verify the API is actually serving
        shell: pwsh
        run: |
          $resp = Invoke-WebRequest -Uri "https://localhost/api/health/" -SkipCertificateCheck -UseBasicParsing
          if ($resp.StatusCode -ne 200) { throw "Health check returned $($resp.StatusCode)" }
```

Notes on choices made here:

- **`git -C ../backend reset --hard origin/main`** instead of a nested `actions/checkout` for the sibling repos — GitHub's checkout action anchors paths inside the job's own workspace directory (`_work/infra/infra/...`); reaching *out* to true sibling folders next to it (which is what the compose `build:` contexts require) is simpler and more transparent as a couple of `git` commands than fighting the action's path handling.
- **`concurrency: production-deploy`** guarantees two deploys (e.g. a `backend` merge and a `frontend` merge landing minutes apart) never race and try to `docker compose up --build` at the same time — the second waits for the first to finish rather than overlapping.
- The health check step depends on the fix in [`monitoring-dashboard.md`](monitoring-dashboard.md) — today `/api/health/` is a no-op that returns `200` even if the database is down, so this step will pass even during a real outage until that fix lands. Add it to this workflow, but don't trust it as your only signal until it does.

## 6. Backup before deploying

The `Backup before deploying` step above simply invokes the **existing** `infra/scripts/backup_db.ps1` (Postgres dump + media volume archive, timestamped, default 14-day retention) — nothing new is written here. It runs on every deploy, so a bad release is never more than one restore away from the last known-good state.

## 7. Rollback

- **Code rollback (primary path):** since deploy is just "check out `main` in all three sibling folders, then `up -d --build`," rolling back is the same operation pointed at the previous known-good commit — e.g. `git -C ../backend reset --hard <previous-sha>` (and the same for `frontend`/`infra`), then re-run the build step. This can be a manual `workflow_dispatch` re-run against an older commit, or a small script that takes a SHA argument.
- **Data rollback is not automatic.** If the bad release included a database migration, checking out old code does *not* un-apply it. Use `infra/scripts/restore_db.ps1` against the pre-deploy backup from step 6, following the full walkthrough (and its `PII_FIELD_KEY` warnings) in `infra/docs/manuales/manual-respaldo.md`. Treat this as a deliberate, human-judgment step — never automate a data restore as part of the pipeline itself.

## 8. Secrets

Exactly one new secret is needed: a **fine-grained GitHub Personal Access Token**, scoped to the `infra` repository only, with `Contents: Read and write` permission (needed to fire `repository_dispatch`). Store it as a repository secret named `DEPLOY_DISPATCH_TOKEN` in **both** `backend` and `frontend` (not `infra` — the token needs to *call* infra's API, so it lives where the caller is). Add a final step to each of their existing `ci.yml` `test`/`build` jobs:

```yaml
      - name: Trigger deploy
        if: github.ref == 'refs/heads/main'
        run: |
          curl -X POST \
            -H "Authorization: Bearer ${{ secrets.DEPLOY_DISPATCH_TOKEN }}" \
            -H "Accept: application/vnd.github+json" \
            https://api.github.com/repos/<org-or-user>/medicalconsultations-infra/dispatches \
            -d '{"event_type":"deploy"}'
```

No other secrets are required — the runner already has local access to `.env` on the server (it's not fetched or generated by the workflow), and the deploy steps run as the same local user that manages the stack manually today.

## 9. Resource footprint

You flagged that the server is likely lower-spec than a development laptop, with real specs still pending — this is addressed head-on rather than glossed over:

- The runner agent itself is small and idle almost all the time (it's a lightweight polling client, comparable to a background sync agent); it does not meaningfully add to steady-state load.
- The actual heavy step — `docker compose ... up -d --build`, which compiles the frontend and installs backend dependencies inside the image build — is **exactly what already runs on that machine today**, manually, every time someone deploys. This pipeline does not add new work to the server; it only automates *triggering* work that already happens there.
- What it *does* add: the possibility of two builds overlapping if pushes land close together — mitigated by the `concurrency` group in step 5, which serializes them.
- Once you have real server specs: if builds run slowly or memory pressure shows up, the first things to consider are (a) whether `npm ci`/Vite build should run with `--max-old-space-size` capped, and (b) whether `docker compose build` needs a `--memory` limit per service during the build stage. Neither is set up here since it's premature without real numbers — flagged for when you have them.

## 10. End-to-end verification checklist

"Delivered and verified" for one pipeline run means, concretely:

- [ ] The GitHub Actions run for `deploy.yml` shows every step green — its log is the audit trail (findable under the `infra` repo's **Actions** tab; the self-hosted runner streams output back to GitHub the same as a cloud runner would).
- [ ] `docker compose -f docker-compose.yml -f docker-compose.prod.yml ps` on the server shows all five containers `running`, with `db`/`cache` (and `backend`/`frontend`/`communications_worker` once [`monitoring-dashboard.md`](monitoring-dashboard.md)'s healthcheck additions land) reporting `healthy`.
- [ ] `https://<server-ip>/api/health/` returns `200` with real dependency checks passing (again, post the fix in Manual 2).
- [ ] A quick manual smoke pass — log in, open a patient record — or, if lightweight enough to run unattended, one of the existing `infra/scripts/qa_*.ps1` scripts (`qa_live_verification.ps1` or `qa_integration_smoke.ps1` are the closest fit for a post-deploy check; the fuller `qa_full_verification.ps1`/`qa_rbac_matrix.ps1` are heavier and better suited to a scheduled or on-demand run than every single deploy).

## See also

- [`monitoring-dashboard.md`](monitoring-dashboard.md) — the health-check fix this pipeline's verification step depends on, plus a dashboard for watching the deployed stack afterward.
- [`manual-despliegue.md`](manuales/manual-despliegue.md) / [`deployment-guide.md`](deployment-guide.md) — the manual process this pipeline automates, and the network/VPN chapter referenced above.
- [`manual-respaldo.md`](manuales/manual-respaldo.md) — full backup/restore walkthrough referenced in the rollback section.
