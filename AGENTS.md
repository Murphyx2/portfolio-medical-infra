# Project Agents

This project has two specialized sub-agents configured for independent security scanning and QA verification. Their instructions are defined locally in `.claude/agents/{security,qa}.md` (not committed to git).

## ⚠️ Invocation mechanism (read this before assuming it "just works")

This runtime does **not** support native custom `subagent_type` registration from `.claude/agents/*.md` — confirmed by testing: even an officially-installed Anthropic plugin agent (`agent-sdk-verifier-py`, under `~/.claude/plugins/marketplaces/.../agents/`) does not appear in this session's available-agent list (`claude`, `claude-code-guide`, `Explore`, `general-purpose`, `Plan`, `statusline-setup` — a fixed set). This isn't a frontmatter bug; the dispatcher here just doesn't consult those files dynamically.

**Working mechanism:** the main agent reads the full content of `.claude/agents/security.md` or `.claude/agents/qa.md` and passes it *as the prompt itself* to `Agent(subagent_type: "general-purpose", ...)`. Since a fresh `general-purpose` agent starts with zero context, embedding the whole mission brief in the prompt reproduces the same behavior a native named sub-agent would have — it's just wired through the prompt instead of a registry lookup. `general-purpose` has unrestricted tool access (`Tools: *`), which covers everything both agents need (Read/Grep/Glob/Bash/Write/Edit).

**Practical effect for you:** none — the trigger phrases below still work exactly the same. This section is here so a future continuation agent doesn't waste a session re-discovering that native registration is a dead end in this environment.

## Security Agent

**Trigger:** "Make a security scan of the app" or similar natural language (e.g., "Run a security audit", "Security review please", "Check for vulnerabilities")

**Workflow:**
1. Security agent scans codebase, dependencies, live services for vulnerabilities.
2. Returns a **severity-categorized report** (CRITICAL/HIGH/MEDIUM/LOW/INFO) with:
   - Component (file:line)
   - Description + evidence (command output, HTTP status, code snippet)
   - Recommended fix
3. You review the findings.
4. **Approval step:** You respond with verbal confirmation (e.g., "Looks good, proceed" or "Skip finding 3, fix 1 and 2").
5. Main agent executes approved fixes and updates code.

**Severity tiers:**
- **CRITICAL** — immediate exploitable risk (RCE, auth bypass, data exfil). Blocks deployment.
- **HIGH** — significant gap (weak crypto, missing validation, credential exposure). Fix before public access.
- **MEDIUM** — defense-in-depth risk (info leakage, weak defaults, incomplete masking). Next sprint.
- **LOW** — cosmetic or low-likelihood risk. Can defer.
- **INFO** — observation or best-practice note.

**Agent capabilities:**
- Reads all files (code, config, migrations, tests).
- Runs dependency scanners (`pip list`, `npm audit`).
- Makes read-only HTTP probes (no destructive exploits).
- Writes automated security test cases (pytest/vitest, infra scripts).
- **Does NOT** modify application code — reports only.

**Checklist covered:**
- Secrets & config (gitignore, env hygiene, key rotation docs)
- Dependencies (pip-audit, npm audit, CVE versions)
- Django hardening (DEBUG, SECRET_KEY, ALLOWED_HOSTS, middleware, headers)
- AuthN/AuthZ (JWT config, password policy, throttling, RBAC matrix, no IDOR)
- Data protection (PII encryption, role-based masking, no PII in logs, media validation)
- Injection & XSS (ORM/parameterized queries, no mark_safe, upload sanitization)
- Infrastructure (DB/Redis loopback, env injection, prod compose, nginx proxying)
- Error handling (no stack traces, safe messages, logging discipline)
- Caching (signal-based invalidation, PHI never cached, schema permission-safe)

---

## QA Agent

**Trigger:** Automatically invoked by main agent after code changes land on `main`, or manually with "Run QA" / "Test the app" / "Verify everything works"

**Workflow:**
1. QA agent runs full test suite (pytest backend, vitest frontend, build).
2. Executes RBAC matrix, PII masking, JWT rotation, throttling, E2E smoke tests.
3. Returns **pass/fail summary** with evidence:
   - Test counts (210 pytest, 36 vitest expected)
   - Any failures listed verbatim
   - RBAC matrix (role × endpoint access verified)
   - PII masking confirmed per role
   - JWT rotation + blacklist working
   - Login throttle firing at 429 on attempt ~11
   - E2E smoke flow complete
4. **No approval step** — QA agent reports results; if all pass, work is verified. If failures, main agent investigates and reports bugs to you for review.

**Autonomy:**
- Executes tests without waiting for approval.
- Adds missing tests automatically (regression tests, new coverage).
- Runs the suite after full-stack changes land (waits if changes span frontend + backend).
- **Does NOT** modify application code — only test code.

**Baselines (as of 2026-08-10):**
- Backend: **210 pytest** passing
- Frontend: **36 vitest** passing + `tsc -b && vite build` clean
- RBAC matrix: 54 cells (6 roles × 9 endpoint pairs) all verified
- PII masking: ADMIN/DOCTOR/NURSE/RECEPTIONIST see full; IT/CENTER_MANAGER masked
- JWT: refresh rotation + blacklist + logout cleared
- Throttle: 429 on login attempt ~11
- E2E: center → medicine → doctor → patient → appointment → record → log → image → detail → media token ✓

**Checklist covered:**
- Backend & frontend tests
- RBAC matrix (role access per endpoint)
- PII masking (full vs masked output)
- JWT rotation & blacklist
- Login throttle (10/min per IP)
- E2E smoke flow
- Search & sorting (encrypted columns client-side)
- Media token validation
- Reference-list caching + invalidation
- Schema cache permission safety

**Timing notes:**
- If you change backend only: QA runs once backend is merged to `main`.
- If you change frontend only: QA runs once frontend is merged to `main`.
- If you change both (e.g., API schema changes + new UI): QA waits for **both** to merge, then runs once.
- **Login throttle race:** Wait ~70s between independent QA runs (throttle is 10/min per IP, and QA deliberately fires ~11 logins).

---

## How to invoke

### Security Agent
In the conversation with Claude Code:
```
Make a security scan of the app
```
or
```
Run a security audit and report vulnerabilities
```
or
```
Security review please — check for CVEs and auth gaps
```

The agent will return a severity-categorized report. You review and respond with approval:
```
Looks good, proceed with all fixes
```
or
```
Approve findings 1, 3, 5 — skip finding 2
```

### QA Agent
**Automatic:** After you commit code changes to backend/frontend/infra and they're merged to `main`, the main agent will invoke QA autonomously at the right time (after full-stack changes land, respecting the throttle cooldown).

**Manual:** In the conversation with Claude Code:
```
Run QA on the app
```
or
```
Execute the full test suite
```

The agent will run all checks and report results. No approval needed — you'll see the pass/fail summary and any bugs to fix.

---

## For Future Continuation

If another Claude instance takes over this project:
1. These two agent definitions are in `.claude/agents/` (local, not git-tracked) — treat them as **prompt templates to embed**, not as registrable subagent types. See the invocation-mechanism note above before trying `subagent_type: "security"` or `"qa"` directly — it will fail with "Agent type not found."
2. They are project-aware: read `infra/PROGRESS.md` for context, aware of the current test counts and recent changes.
3. Severity tiers (CRITICAL/HIGH/MEDIUM/LOW/INFO) are the currency for prioritizing security fixes.
4. QA autonomy is intentional: tests are cheap to run and safe to add; the main agent calls QA after changes land.
5. **Never override without consensus:** If a future agent wants to change agent behavior (e.g., approval gates, baselines), discuss with the project stakeholders (you) first.
6. If a future session finds that native `.claude/agents/*.md` registration *does* work (e.g., the harness was upgraded), that's a strict improvement — switch to `subagent_type: "security"`/`"qa"` directly and drop the prompt-embedding workaround.

---

## Customization

To update baselines (test counts, checklist items, etc.) as the project evolves:
1. Edit `.claude/agents/qa.md` (baseline test counts) and `.claude/agents/security.md` (checklist, known areas) to reflect new state.
2. These files are not committed; they live only in the Claude Code session/project config.
3. Update `infra/PROGRESS.md` with major milestones (new audit passes, new test suites) for continuity.
