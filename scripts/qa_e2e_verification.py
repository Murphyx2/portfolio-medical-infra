"""Live-stack E2E QA verification for MedicalConsultations.

Run:  backend/.venv/Scripts/python.exe infra/scripts/qa_e2e_verification.py
(or any python with `requests`). Requires the docker stack (api :8000) to be up.

Covers:
  - new phone validation (digits-only, 10-digit rule, letters rejected)
  - phone formatting end-to-end + DB storage check (via docker exec)
  - masked PII (IT/CM) not mangled
  - varied names/genders + all patient form fields (cedula, nss, email, birth_date, gender)
  - center / doctor phone required checks
  - RBAC matrix for the 6 roles x core endpoints
  - records detail readable by ALL staff roles (patient-name click backend path)
  - JWT refresh rotation + blacklist, logout
  - login throttle (429)
  - full E2E smoke: center -> medicine -> doctor -> patient -> appointment(cancel) -> record+log+image
  - schema/docs gating

Exit code 0 = all pass, 1 = at least one FAIL.
"""

import base64
import json
import random
import subprocess
import sys
import time
import zlib
import struct

import requests

BASE = "http://localhost:8000/api"
RUN = str(random.randint(100000, 999999))
MASK = "\u2022"  # bullet '•'

PASS = []
FAIL = []


def report(name, ok, detail=""):
    tag = "PASS" if ok else "FAIL"
    line = f"{tag}  {name}"
    if detail:
        line += f"  [{detail}]"
    print(line)
    if ok:
        PASS.append(name)
    else:
        FAIL.append(name)


def call(method, path, token=None, body=None, files=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        r = requests.request(
            method, BASE + path, headers=headers, json=body, files=files, timeout=40
        )
    except requests.RequestException as e:
        return -1, {"_error": str(e)}
    try:
        data = r.json()
    except Exception:
        data = r.text
    return r.status_code, data


def login(username, password):
    """Login with one retry after 60s if throttled."""
    for attempt in range(2):
        st, data = call("POST", "/auth/login/", body={"username": username, "password": password})
        if st == 429 and attempt == 0:
            print("    (login throttled; waiting 60s before retry)")
            time.sleep(60)
            continue
        return st, data
    return st, data


def sess_call(method, path, sess, token=None, body=None):
    """Request that rides a persistent requests.Session (cookie jar)."""
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        r = sess.request(method, BASE + path, headers=headers, json=body, timeout=40)
    except requests.RequestException as e:
        return -1, {"_error": str(e)}
    try:
        data = r.json()
    except Exception:
        data = r.text
    return r.status_code, data


def db_check(patient_id, field="phone"):
    """Read the value straight from Postgres via the container's Django ORM."""
    code = (
        "from apps.patients.models import Patient;"
        f"print(Patient.objects.get(pk={patient_id}).{field})"
    )
    try:
        out = subprocess.run(
            ["docker", "exec", "mc_backend", "python", "manage.py", "shell", "-c", code],
            capture_output=True, text=True, timeout=60,
        )
    except Exception as e:
        return f"<db check failed: {e}>"
    lines = [ln.strip() for ln in out.stdout.splitlines() if ln.strip() and "objects imported" not in ln and not ln.strip().startswith("(use -v 2")]
    return lines[-1] if lines else "<empty>"


def make_png_bytes(width=2, height=2):
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        c += struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        return c

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * width for _ in range(height))
    idat = zlib.compress(raw)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


# ---------------------------------------------------------------- auth setup
print(f"=== QA run {RUN} | {time.strftime('%H:%M:%S')} ===")
creds = {
    "ADMIN": ("admin", "AdminPass123!"),
    "DOCTOR": ("doctor", "Pass123!x"),
    "RECEPTIONIST": ("receptionist", "Pass123!x"),
    "NURSE": ("nurse", "Pass123!x"),
    "IT": ("it", "Pass123!x"),
    "CENTER_MANAGER": ("cm", "Pass123!x"),
}
tokens = {}
for role, (u, p) in creds.items():
    st, data = login(u, p)
    if st == 200 and data.get("access"):
        tokens[role] = data["access"]
        print(f"    login {role:14} OK")
    else:
        print(f"    login {role:14} -> {st} {data}")
        sys.exit(f"cannot login as {role}: {st} {data}")
report("login: all six roles", len(tokens) == 6, ",".join(tokens))

# ---------------------------------------------------------------- phone validation (backend)
print("--- Phone validation & formatting E2E ---")
# 1) formatted input stored digits-only
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Fon", "last_name": "Tono", "gender": "MALE",
    "phone": "(809) 555-1212", "email": "fono@example.com",
    "cedula": "001-1234567-8", "nss": "01234567890",
})
phone_patient_id = data.get("id")
report("patient phone (809) 555-1212 -> 201 & stored digits", st == 201 and data.get("phone") == "8095551212",
       f"status={st} api_phone={data.get('phone')}")
db_val = db_check(phone_patient_id) if phone_patient_id else None
report("patient phone stored digits-only in Postgres", db_val == "8095551212", f"db={db_val!r}")

# 2) letters rejected
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Bad", "last_name": "Phone", "gender": "FEMALE", "phone": "abc80955512"})
report("patient phone with letters -> 400", st == 400 and "phone" in data, f"status={st} body={str(data)[:120]}")
# 3) 9 digits rejected
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Bad", "last_name": "Phone", "gender": "FEMALE", "phone": "809-555-121"})
report("patient phone 9 digits -> 400", st == 400, f"status={st}")
# 4) 11 digits rejected
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Bad", "last_name": "Phone", "gender": "FEMALE", "phone": "80955512123"})
report("patient phone 11 digits -> 400", st == 400, f"status={st}")
# 5) empty optional
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "No", "last_name": "Phone", "gender": "UNSPECIFIED", "phone": ""})
report("patient phone empty -> 201 (optional)", st == 201 and data.get("phone") == "", f"status={st}")
# 6) PATCH normalization
patch_id = phone_patient_id
st, data = call("PATCH", f"/patients/{patch_id}/", token=tokens["RECEPTIONIST"], body={"phone": "829 555 0199"})
report("PATCH phone '829 555 0199' -> 8295550199", st == 200 and data.get("phone") == "8295550199", f"status={st} phone={data.get('phone')}")

# 7) center phone required + normalized
st, data = call("POST", "/centers/", token=tokens["ADMIN"], body={
    "name": f"Centro {RUN}", "code": f"CT{RUN}", "address": "Av 1", "phone": "(809) 555-1212"})
center_id = data.get("id")
report("center phone required+normalized", st == 201 and data.get("phone") == "8095551212", f"status={st} phone={data.get('phone')}")
st, data = call("POST", "/centers/", token=tokens["ADMIN"], body={
    "name": f"Centro NoTel {RUN}", "code": f"CN{RUN}", "address": "Av 2"})
report("center without phone -> 400 (required)", st == 400, f"status={st} body={str(data)[:120]}")

# 8) doctor contact_phone required + normalized
st, data = call("POST", "/auth/users/", token=tokens["ADMIN"], body={
    "username": f"docqa{RUN}", "email": f"docqa{RUN}@example.com", "password": "Pass123!x",
    "role": "DOCTOR", "first_name": "Doc", "last_name": "QA"})
new_doc_user_id = data.get("id")
st, data = call("POST", "/doctors/profiles/", token=tokens["ADMIN"], body={
    "user": new_doc_user_id, "specialty": "Cardiology", "license_number": f"LIC-QA-{RUN}",
    "contact_phone": "(809) 555-1212"})
report("doctor contact_phone normalized", st == 201 and data.get("contact_phone") == "8095551212",
       f"status={st} phone={data.get('contact_phone')}")
st, data = call("POST", "/doctors/profiles/", token=tokens["ADMIN"], body={
    "user": new_doc_user_id, "specialty": "Cardiology", "license_number": f"LIC-QA2-{RUN}"})
report("doctor profile without contact_phone -> 400", st == 400, f"status={st}")

# 9) masked phone for IT/CM (mask pattern from PatientSerializer._mask: 2 + 4 bullets + 2)
st_it, d_it = call("GET", f"/patients/{patch_id}/", token=tokens["IT"])
st_cm, d_cm = call("GET", f"/patients/{patch_id}/", token=tokens["CENTER_MANAGER"])
masked_ok = (
    d_it.get("phone", "").count(MASK) == 4 and d_cm.get("phone", "").count(MASK) == 4
    and d_it.get("phone") == d_cm.get("phone")
)
report("IT/CM see masked phone (not mangled, 4 bullets)", masked_ok,
       f"IT={d_it.get('phone')} CM={d_cm.get('phone')} raw=8295550199")

# 10) doctor sees full digits
st, d_doc = call("GET", f"/patients/{patch_id}/", token=tokens["DOCTOR"])
report("doctor sees full phone digits", st == 200 and d_doc.get("phone") == "8295550199",
       f"phone={d_doc.get('phone')}")

# ---------------------------------------------------------------- varied patients + field validation
print("--- Varied names/genders + patient form fields ---")
varied = [
    ("Juan", "Delgado", "MALE", "(809) 111-2222"),
    ("María José", "Álvarez", "FEMALE", "(829) 333-4444"),
    ("Alex", "Rivera", "OTHER", "(849) 555-6666"),
    ("Štefan", "O'Brien-Walsh", "MALE", "(809) 777-8888"),
    ("Xiomara", "Peña", "FEMALE", ""),
    ("Noor", "Al-Hassan", "UNSPECIFIED", "(809) 999-0000"),
]
for fn, ln, g, ph in varied:
    st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
        "first_name": fn, "last_name": ln, "gender": g, "phone": ph})
    report(f"patient {fn} {ln} ({g})", st == 201, f"status={st}")

st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Bad", "last_name": "Gender", "gender": "BANANA"})
report("gender BANANA -> 400 (choices enforced)", st == 400, f"status={st} body={str(data)[:120]}")

# cedula validation
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Ced", "last_name": "Ula", "gender": "FEMALE", "cedula": "123-4567890-1"})
ced_patient_id = data.get("id")
report("cedula 123-4567890-1 normalized to 11 digits", st == 201 and data.get("cedula") == "12345678901",
       f"status={st} cedula={data.get('cedula')}")
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Ced", "last_name": "Short", "gender": "FEMALE", "cedula": "12345"})
report("cedula <11 digits -> 400", st == 400, f"status={st} body={str(data)[:120]}")
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Ced", "last_name": "Alpha", "gender": "FEMALE", "cedula": "abcdefg"})
report("cedula letters-only -> 400", st == 400, f"status={st} body={str(data)[:120]}")

# nss validation
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Nss", "last_name": "One", "gender": "MALE", "nss": "01234567890"})
report("nss digits ok (11 max)", st == 201 and data.get("nss") == "01234567890", f"status={st}")
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Nss", "last_name": "Bad", "gender": "MALE", "nss": "ABC12345"})
report("nss letters -> 400", st == 400, f"status={st} body={str(data)[:120]}")

# email validation (EncryptedCharField -> CharField serializer; no EmailField validator)
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Mail", "last_name": "Bad", "gender": "FEMALE", "email": "not-an-email"})
report("patient email 'not-an-email' rejected (MISSING VALIDATION?)", st == 400, f"status={st} -> ACCEPTED={st == 201}")

# birth_date validation (EncryptedCharField; no date validator)
st, data = call("POST", "/patients/", token=tokens["RECEPTIONIST"], body={
    "first_name": "Date", "last_name": "Bad", "gender": "FEMALE", "birth_date": "not-a-date"})
report("birth_date 'not-a-date' rejected (MISSING VALIDATION?)", st == 400, f"status={st} -> ACCEPTED={st == 201}")

# doctor license required/duplicate
st, data = call("POST", "/auth/users/", token=tokens["ADMIN"], body={
    "username": f"doclic{RUN}", "email": f"doclic{RUN}@example.com", "password": "Pass123!x",
    "role": "DOCTOR", "first_name": "Lic", "last_name": "Ense"})
lic_user = data.get("id")
st, data = call("POST", "/doctors/profiles/", token=tokens["ADMIN"], body={
    "user": lic_user, "specialty": "Pediatría", "contact_phone": "8095550101"})
report("doctor profile missing license_number -> 400 (required)", st == 400, f"status={st}")
st, data = call("POST", "/doctors/profiles/", token=tokens["ADMIN"], body={
    "user": lic_user, "specialty": "Pediatría", "license_number": f"LIC-DUP-{RUN}", "contact_phone": "8095550101"})
report("doctor profile license ok", st == 201, f"status={st}")
st, data = call("POST", "/doctors/profiles/", token=tokens["ADMIN"], body={
    "user": new_doc_user_id, "specialty": "Cardio", "license_number": f"LIC-DUP-{RUN}", "contact_phone": "8095550101"})
report("duplicate doctor license_number -> 400", st == 400, f"status={st} body={str(data)[:120]}")

# ---------------------------------------------------------------- RBAC matrix
print("--- RBAC matrix (6 roles x endpoints) ---")
# ensure base data
med_generic = f"ParaQA-{RUN}"
st, data = call("POST", "/medicines/", token=tokens["ADMIN"], body={
    "generic_name": med_generic, "commercial_name": f"QAcol-{RUN}", "concentration": "500 mg"})
med_id = data.get("id")
st, data = call("POST", "/ars/", token=tokens["ADMIN"], body={
    "ars_id": f"QA{RUN}", "name": f"ARS QA {RUN}", "programs": [{"name": "Básico"}]})
ars_id = data.get("id")
# doctor profile of the `doctor` account (server-side search: the DB is large
# enough that the default 20-row first page no longer contains the doctor user)
st, data = call("GET", "/auth/users/?search=doctor", token=tokens["ADMIN"])
docu = next((u for u in data.get("results", []) if u.get("username") == "doctor"), None)
doc_profile = None
if docu:
    st, data = call("GET", f"/doctors/profiles/?user={docu['id']}", token=tokens["ADMIN"])
    doc_profile = next((p for p in data.get("results", []) if p.get("username") == "doctor"), None)
if not doc_profile and docu:
    st, data = call("POST", "/doctors/profiles/", token=tokens["ADMIN"], body={
        "user": docu["id"], "specialty": "Cardiology", "license_number": f"LIC-DOC-{RUN}",
        "contact_phone": "8095551212"})
    doc_profile = data
doc_profile_id = doc_profile.get("id")

# (the doctor-profiles POST payload below creates its own throwaway users)

ROLES = ["ADMIN", "DOCTOR", "RECEPTIONIST", "NURSE", "IT", "CENTER_MANAGER"]
# (endpoint, GET_allowed, POST_allowed)  GET_allowed: set of roles with read access
matrix = [
    ("/auth/users/",          {"ADMIN", "IT"}, {"ADMIN", "IT"}),
    ("/centers/",             "all", {"ADMIN", "IT"}),
    ("/medicines/",           "all", {"ADMIN", "IT"}),
    ("/doctors/profiles/",    "all", {"ADMIN", "IT"}),
    ("/patients/",            "all", {"ADMIN", "DOCTOR", "RECEPTIONIST"}),
    ("/medical-records/",     "all", {"ADMIN", "DOCTOR", "NURSE"}),
    ("/consultation-logs/",   "all", {"ADMIN", "DOCTOR", "NURSE"}),
    ("/appointments/",        "all", {"ADMIN", "DOCTOR", "RECEPTIONIST"}),
    ("/ars/",                 "all", {"ADMIN", "RECEPTIONIST"}),
]
# payload builders (unique per endpoint/role to avoid unique-constraint 400s)
def post_payload(endpoint, role, seq):
    if endpoint == "/centers/":
        return {"name": f"RBAC {role} {RUN}-{seq}", "code": f"RB{role}{RUN}{seq}", "address": "Av X", "phone": "8095551111"}
    if endpoint == "/medicines/":
        return {"generic_name": f"RbQA-{role}-{RUN}-{seq}", "commercial_name": f"RbC-{seq}", "concentration": "250 mg"}
    if endpoint == "/doctors/profiles/":
        # fresh user per role attempt (a user can have only one profile)
        st_, user_ = call("POST", "/auth/users/", token=tokens["ADMIN"], body={
            "username": f"docprof{RUN}{role}{seq}", "email": f"docprof{RUN}{role}{seq}@example.com",
            "password": "Pass123!x", "role": "DOCTOR", "first_name": "P", "last_name": role})
        uid = user_.get("id")
        return {"user": uid, "specialty": "General", "license_number": f"LIC-RBAC-{RUN}-{role}-{seq}", "contact_phone": "8095552222"}
    if endpoint == "/patients/":
        return {"first_name": f"RBAC{seq}", "last_name": role, "gender": "MALE", "phone": ""}
    if endpoint == "/medical-records/":
        return {"patient": phone_patient_id, "title": f"RBAC rec {role} {seq}", "diagnosis": "x"}
    if endpoint == "/consultation-logs/":
        return {"patient": phone_patient_id, "subjective": f"rbac {role} {seq}"}
    if endpoint == "/appointments/":
        return {"patient": phone_patient_id, "doctor": doc_profile_id,
                "date_time": "2026-12-01T10:00:00Z", "notes": f"rbac {role} {seq}"}
    if endpoint == "/ars/":
        return {"ars_id": f"A{role[:3]}{RUN}{seq}", "name": f"ARS {role} {RUN} {seq}"}
    if endpoint == "/auth/users/":
        return {"username": f"u{role}{RUN}{seq}", "email": f"u{role}{RUN}{seq}@example.com",
                "password": "Pass123!x", "role": "RECEPTIONIST", "first_name": "U", "last_name": "X"}
    return {}

rbac_fail = []
for endpoint, get_allowed, post_allowed in matrix:
    # GET
    for role in ROLES:
        st, _ = call("GET", endpoint, token=tokens[role])
        exp = 200 if (get_allowed == "all" or role in get_allowed) else 403
        ok = st == exp
        if not ok:
            rbac_fail.append(f"GET {endpoint} as {role}: got {st} exp {exp}")
        report(f"RBAC GET {endpoint} as {role:14}", ok, f"got={st}")
    # POST (one attempt per role)
    seq = 0
    for role in ROLES:
        seq += 1
        payload = post_payload(endpoint, role, seq)
        st, data = call("POST", endpoint, token=tokens[role], body=payload)
        exp = 201 if role in post_allowed else 403
        ok = st == exp
        if not ok:
            rbac_fail.append(f"POST {endpoint} as {role}: got {st} exp {exp} body={str(data)[:100]}")
        report(f"RBAC POST {endpoint} as {role:14}", ok, f"got={st} exp={exp}")
report("RBAC matrix (54 cells)", len(rbac_fail) == 0, f"failures={len(rbac_fail)}")

# ---------------------------------------------------------------- records read for ALL roles (patient-name click path)
print("--- Records detail readable by all staff roles ---")
st, data = call("POST", "/medical-records/", token=tokens["DOCTOR"], body={
    "patient": phone_patient_id, "title": f"QA record {RUN}",
    "diagnosis": "Hipertensión arterial", "treatment": "Losartán 50 mg c/12h",
    "medicine_and_doses": "Losartán 50 mg", "notes": "Seguimiento mensual"})
rec_id = data.get("id")
report("record created by doctor", st == 201, f"status={st} id={rec_id}")
rec_read_fail = []
MASKED_ROLES = ("IT", "CENTER_MANAGER")
for role in ROLES:
    st, data = call("GET", f"/medical-records/{rec_id}/", token=tokens[role])
    name = data.get("patient_info", {}).get("full_name")
    # H-04/M-05: IT and CENTER_MANAGER see masked names (still navigable click path);
    # the other roles see the full name.
    if role in MASKED_ROLES:
        name_ok = (name is not None) and (name != "Fon Tono") and ("\u2022" in name)
    else:
        name_ok = name == "Fon Tono"
    ok = st == 200 and name_ok
    if not ok:
        rec_read_fail.append(f"{role}: got {st} full_name={name}")
    label = "masked" if role in MASKED_ROLES else "visible"
    report(f"record detail GET as {role:14} (patient name {label})", ok, f"got={st} name={name}")
    st2, logs = call("GET", f"/consultation-logs/?patient={phone_patient_id}", token=tokens[role])
    if st2 != 200:
        rec_read_fail.append(f"{role} consultation-logs list: {st2}")
report("records+logs readable for all 6 roles", len(rec_read_fail) == 0, f"failures={len(rec_read_fail)}")

# clinical masking on records for non-clinical roles
st, d_it = call("GET", f"/medical-records/{rec_id}/", token=tokens["IT"])
st, d_doc = call("GET", f"/medical-records/{rec_id}/", token=tokens["DOCTOR"])
report("record clinical fields masked for IT, full for doctor",
       MASK in d_it.get("diagnosis", "") and d_doc.get("diagnosis") == "Hipertensión arterial",
       f"IT={d_it.get('diagnosis')!r} DOCTOR={d_doc.get('diagnosis')!r}")

# ---------------------------------------------------------------- PII masking
print("--- PII masking ---")
full_roles = ["ADMIN", "DOCTOR", "RECEPTIONIST", "NURSE"]
mask_roles = ["IT", "CENTER_MANAGER"]
pii_fail = []
st, d_rec = call("GET", f"/patients/{patch_id}/", token=tokens["RECEPTIONIST"])
raw_email = d_rec.get("email")
for role in full_roles:
    st, d = call("GET", f"/patients/{patch_id}/", token=tokens[role])
    ok = st == 200 and d.get("email") == raw_email and d.get("phone") == "8295550199" and d.get("first_name") == "Fon"
    if not ok:
        pii_fail.append(f"{role}: email={d.get('email')} phone={d.get('phone')} name={d.get('first_name')}")
    report(f"PII full for {role:14}", ok, f"email={d.get('email')}")
for role in mask_roles:
    st, d = call("GET", f"/patients/{patch_id}/", token=tokens[role])
    ok = (st == 200 and d.get("email") != raw_email and d.get("phone") != "8295550199"
          and d.get("first_name") != "Fon" and d.get("age") is None)
    if not ok:
        pii_fail.append(f"{role}: email={d.get('email')} phone={d.get('phone')} name={d.get('first_name')} age={d.get('age')}")
    report(f"PII masked for {role:14}", ok,
           f"email={d.get('email')} phone={d.get('phone')} name={d.get('first_name')} age={d.get('age')}")
report("PII masking per role", len(pii_fail) == 0, f"failures={len(pii_fail)}")

# ---------------------------------------------------------------- JWT rotation + logout
print("--- JWT rotation + logout (httpOnly cookie) ---")


def login_sess(sess, username, password):
    return sess_call("POST", "/auth/login/", sess, body={"username": username, "password": password})


sess = requests.Session()
st, lr = login_sess(sess, "admin", "AdminPass123!")
report("login (cookie session) -> 200, access only in body",
       st == 200 and "access" in lr and "refresh" not in lr, f"status={st}")
old_cookie = sess.cookies.get("mc_refresh")
report("httpOnly refresh cookie set on login", st == 200 and bool(old_cookie), f"cookie_set={bool(old_cookie)}")

st, rot = sess_call("POST", "/auth/token/refresh/", sess)
new_cookie = sess.cookies.get("mc_refresh")
report("refresh via cookie rotates (new access + rotated cookie)",
       st == 200 and rot.get("access") and new_cookie and new_cookie != old_cookie,
       f"status={st} rotated={new_cookie != old_cookie}")
sess.cookies.set("mc_refresh", old_cookie, path="/api/auth/")
st, reuse = sess_call("POST", "/auth/token/refresh/", sess)
report("reusing OLD cookie after rotation -> 401 blacklisted", st == 401, f"status={st}")

# logout
sess2 = requests.Session()
st, lr2 = login_sess(sess2, "admin", "AdminPass123!")
acc2 = lr2.get("access")
st, _ = sess_call("POST", "/auth/logout/", sess2, token=acc2)
report("logout -> 204", st == 204, f"status={st}")
report("logout clears the refresh cookie", sess2.cookies.get("mc_refresh") in (None, ""),
       f"cookie={sess2.cookies.get('mc_refresh')!r}")
st, reuse2 = sess_call("POST", "/auth/token/refresh/", sess2)
report("refresh after logout -> 401", st == 401, f"status={st}")
st, me = call("GET", "/auth/me/", token=acc2)
report("access token still works after logout (access not blacklisted)", st == 200,
       f"status={st} (LogoutView blacklists refresh only; access valid till expiry)")

# ---------------------------------------------------------------- schema/docs gating
print("--- Schema / docs gating ---")
st_a, _ = call("GET", "/schema/")
st_d, _ = call("GET", "/docs/")
st_adm, _ = call("GET", "/schema/", token=tokens["ADMIN"])
st_it, _ = call("GET", "/schema/", token=tokens["IT"])
st_dr, _ = call("GET", "/schema/", token=tokens["DOCTOR"])
report("schema/docs gating (anon 401, admin/IT 200, doctor 403)",
       st_a == 401 and st_d == 401 and st_adm == 200 and st_it == 200 and st_dr == 403,
       f"anon={st_a}/{st_d} admin={st_adm} it={st_it} doctor={st_dr}")

# ---------------------------------------------------------------- login throttle
print("--- Login throttle ---")
throttled_at = None
for i in range(12):
    st, _ = call("POST", "/auth/login/", body={"username": f"throttleuser{RUN}{i}", "password": "wrongpass"})
    if st == 429:
        throttled_at = i + 1
        break
report("login throttle returns 429", throttled_at is not None,
       f"429 on rapid attempt {throttled_at}" if throttled_at else "no 429 observed in 12 rapid attempts")

# ---------------------------------------------------------------- full E2E smoke
print("--- E2E smoke flow ---")
smoke_fail = []
# center (already created), medicine (created), doctor profile (doc_profile_id)
# appointment create (receptionist) + cancel
st, data = call("POST", "/appointments/", token=tokens["RECEPTIONIST"], body={
    "patient": phone_patient_id, "doctor": doc_profile_id, "center": center_id,
    "date_time": "2026-11-15T09:30:00Z", "duration_minutes": 30, "notes": "Cita E2E"})
appt_id = data.get("id")
ok = st == 201
if not ok:
    smoke_fail.append(f"appointment create: {st} {data}")
report("E2E appointment created", ok, f"status={st}")
st, data = call("PATCH", f"/appointments/{appt_id}/", token=tokens["RECEPTIONIST"], body={"status": "CANCELLED"})
ok = st == 200 and data.get("status") == "CANCELLED"
if not ok:
    smoke_fail.append(f"appointment cancel: {st} {data}")
report("E2E appointment cancelled", ok, f"status={st} status={data.get('status')}")

# consultation log (doctor)
st, data = call("POST", "/consultation-logs/", token=tokens["DOCTOR"], body={
    "patient": phone_patient_id, "subjective": "Cefalea de 3 días",
    "objective": "TA 130/85", "assessment": "Migraña", "plan": "Reposo y analgésicos", "notes": ""})
log_id = data.get("id")
ok = st == 201
if not ok:
    smoke_fail.append(f"log create: {st} {data}")
report("E2E consultation log created", ok, f"status={st}")

# image upload
png = make_png_bytes()
st, data = call("POST", "/images/", token=tokens["DOCTOR"], files={
    "record": (None, str(rec_id)),
    "caption": (None, "ECG"),
    "image": ("ecg.png", png, "image/png"),
})
ok = st == 201 and data.get("image_url")
if not ok:
    smoke_fail.append(f"image upload: {st} {data}")
report("E2E image uploaded (valid PNG)", ok, f"status={st}")
img_url = data.get("image_url") if ok else None

# record detail includes image; signed media fetch works
st, detail = call("GET", f"/medical-records/{rec_id}/", token=tokens["DOCTOR"])
ok = st == 200 and any(img.get("caption") == "ECG" for img in detail.get("images", []))
if not ok:
    smoke_fail.append(f"record detail images: {st} {detail.get('images')}")
report("E2E record detail shows uploaded image", ok, f"status={st}")
if img_url:
    r = requests.get(img_url, timeout=30)
    ok = r.status_code == 200 and r.content[:8] == b"\x89PNG\r\n\x1a\n"
    if not ok:
        smoke_fail.append(f"media fetch: {r.status_code}")
    report("E2E signed media URL serves the PNG", ok, f"http={r.status_code}")
else:
    report("E2E signed media URL serves the PNG", False, "no image_url")

# invalid image (not a real image) rejected
st, data = call("POST", "/images/", token=tokens["DOCTOR"], files={
    "record": (None, str(rec_id)), "caption": (None, "fake"),
    "image": ("fake.png", b"not really an image", "image/png")})
ok = st == 400
if not ok:
    smoke_fail.append(f"invalid image accepted: {st}")
report("E2E non-image file rejected (400)", ok, f"status={st}")

# oversized image rejected
big = b"\x89PNG\r\n\x1a\n" + b"0" * (5 * 1024 * 1024 + 100)
st, data = call("POST", "/images/", token=tokens["DOCTOR"], files={
    "record": (None, str(rec_id)), "caption": (None, "big"),
    "image": ("big.png", big, "image/png")})
ok = st == 400
if not ok:
    smoke_fail.append(f"oversized image accepted: {st}")
report("E2E >5MB image rejected (400)", ok, f"status={st}")

report("E2E smoke flow (appointment->log->image->detail)", len(smoke_fail) == 0, f"failures={len(smoke_fail)}")

# ---------------------------------------------------------------- summary
print()
print("=" * 70)
print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
for f in FAIL:
    print(f"  FAILED: {f}")
sys.exit(1 if FAIL else 0)
